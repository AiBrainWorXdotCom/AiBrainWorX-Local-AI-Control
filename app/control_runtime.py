"""Loopback-only request settings service and local launcher commands."""
from __future__ import annotations

import argparse
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

import control_core as core
import model_backends as backends
import project_memory as memory
import app_updates
import update_center
import local_chat
import training_local
import backend_budget
import guarded_stream
import session_gateway
import plugin_host
from context_policy import BudgetError, can_continue, fit_request

MAX_BODY = 8 * 1024 * 1024
GET_ROUTES = {'/v1/models', '/models', '/metrics', '/props', '/v1/status'}
POST_ROUTES = {'/v1/responses', '/v1/chat/completions'}
HOP_HEADERS = {'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'content-length'}


def data_identity(config):
    return core.data_identity(config)


def make_server(config, port=8082, upstream_port=None):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass  # Requests, prompts and authorization headers are never logged.

        def reply_json(self, status, value):
            data = json.dumps(value).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Connection', 'close')
            self.end_headers()
            self.close_connection = True
            self.wfile.write(data)

        def do_OPTIONS(self):
            self.reply_json(403, {'error': 'Browser cross-origin requests are not enabled.'})

        def do_GET(self):
            self.forward(False)

        def do_POST(self):
            self.forward(True)

        def forward(self, post):
            connection = None
            chat_session = None
            response_started = False
            try:
                host = self.headers.get('Host', '')
                if host not in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}'):
                    return self.reply_json(403, {'error': 'Loopback Host required.'})
                origin = self.headers.get('Origin')
                if origin and origin not in (f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'):
                    return self.reply_json(403, {'error': 'Cross-origin requests are not enabled.'})
                parsed = urlsplit(self.path)
                route = parsed.path
                if not post and route == '/health':
                    return self.reply_json(200, {'service': 'aibrainworx-control', 'version': core.VERSION, 'dataIdentity': data_identity(config)})
                identity = None
                if route.startswith('/profiles/'):
                    match = re.fullmatch(r'/profiles/([a-zA-Z0-9-]{1,64})(/v1/(?:responses|chat/completions|models))', route)
                    if not match:
                        return self.reply_json(404, {'error': 'Unknown profile route.'})
                    identity, route = match.groups()
                if route not in (POST_ROUTES if post else GET_ROUTES):
                    return self.reply_json(404, {'error': 'Unsupported local API route.'})
                state = core.ensure_state(config)
                profile = core.get_profile(state, identity)
                selected = backends.normalize(profile['model'], config, validate_file=False)
                target_url = urlsplit(selected['baseUrl'])
                if target_url.port == self.server.server_port:
                    raise ValueError('A gateway cannot forward model requests to itself.')
                if not post and route in ('/metrics','/props','/v1/status') and selected['backend'] != 'strata':
                    return self.reply_json(404, {'error': 'This telemetry endpoint is only available from Strata.'})
                body = None
                if post:
                    if self.headers.get_content_type() != 'application/json' or self.headers.get('Transfer-Encoding'):
                        return self.reply_json(400, {'error': 'A bounded JSON request is required.'})
                    try:
                        size = int(self.headers.get('Content-Length', '-1'))
                    except ValueError:
                        size = -1
                    if not 0 <= size <= MAX_BODY:
                        return self.reply_json(413, {'error': 'The request body exceeds the local limit.'})
                    self.connection.settimeout(15)
                    raw = self.rfile.read(size)
                    if len(raw) != size:
                        raise ValueError('Incomplete request body.')
                    request = json.loads(raw)
                    if not isinstance(request, dict):
                        raise ValueError('A JSON object is required.')
                    if request.get('model') and request['model'] != selected['modelId']:
                        return self.reply_json(409, {'error': 'The saved profile model changed. Reopen the client to use its selected model.'})
                    if selected['backend']=='ollama' and (request.get('previous_response_id') or request.get('conversation')):
                        return self.reply_json(400, {'error': 'Ollama requires stateless Responses requests with complete input history.'})
                    def enrich(candidate):
                        context = memory.recall(config,profile,memory.latest_question(candidate,route))['text'] if profile.get('useMemory') else ''
                        candidate = core.transform_request(candidate, profile, route, context)
                        candidate['model'] = selected['modelId']
                        if selected['reasoningEffort']:
                            if route=='/v1/responses':
                                reasoning=candidate.get('reasoning') or {}
                                if not isinstance(reasoning,dict):
                                    raise ValueError('Invalid reasoning configuration.')
                                candidate['reasoning']={**reasoning,'effort':selected['reasoningEffort']}
                            else:
                                candidate['reasoning_effort']=selected['reasoningEffort']
                        return candidate
                    # Counting occurs AFTER profile instructions, project memory and
                    # reasoning settings have been applied. Tokenizers never run inference.
                    strict = selected['backend'] == 'strata' and bool(config.get('StrataRoot'))
                    strict = strict or (selected['backend'] == 'compatible' and route == '/v1/chat/completions')
                    backend = backend_budget.Backend(selected, upstream_port, config, route)
                    if strict:
                        request, chat_session = session_gateway.prepare(config, profile, selected, request, route, backend, enrich)
                    else:
                        request.pop('aibrainworx_session', None)
                        request = enrich(request)
                    if strict:
                        if route == '/v1/chat/completions' and request.get('stream') and can_continue(request):
                            source = guarded_stream.stream(backend, request, profile['maxOutputTokens'], selected['contextWindow'],
                                                          auto_continue=profile.get('autoContinue', True))
                            try:
                                first = next(source)  # Preflight failures remain proper JSON errors.
                                self.send_response(200)
                                self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
                                self.send_header('Cache-Control', 'no-store')
                                self.send_header('Connection', 'close')
                                self.end_headers()
                                response_started = self.close_connection = True
                                if chat_session:
                                    chat_session.record(first)
                                self.wfile.write(first)
                                self.wfile.flush()
                                for item in source:
                                    if chat_session:
                                        chat_session.record(item)
                                    self.wfile.write(item)
                                    self.wfile.flush()
                            finally:
                                source.close()  # A disconnected client never launches another pass.
                            return
                        ctx, prompt_count = backend.preflight(request)
                        request, _ = fit_request(request, prompt_tokens=prompt_count, server_context=ctx,
                                                 profile_limit=profile['maxOutputTokens'], context_ceiling=selected['contextWindow'])
                    body = json.dumps(request, ensure_ascii=False).encode('utf-8')
                connection = HTTPConnection('127.0.0.1', upstream_port or target_url.port, timeout=600 if post else 3)
                headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS | {'host', 'origin', 'accept-encoding','authorization','cookie'}}
                headers.update(backends.headers(selected))
                headers['Accept-Encoding'] = 'identity'
                target = route + ('?' + parsed.query if parsed.query else '')
                connection.request('POST' if post else 'GET', target, body, headers)
                upstream = connection.getresponse()
                self.send_response(upstream.status)
                response_started = True
                for key, value in upstream.getheaders():
                    if key.lower() not in HOP_HEADERS:
                        self.send_header(key, value)
                self.send_header('Connection', 'close')
                self.end_headers()
                self.close_connection = True
                if chat_session and upstream.status == 200:
                    if request.get('stream'):
                        for event in guarded_stream.events(upstream):
                            item = guarded_stream.frame(event)
                            chat_session.record(item)
                            self.wfile.write(item)
                            self.wfile.flush()
                        self.wfile.write(b'data: [DONE]\n\n')
                        self.wfile.flush()
                    else:
                        data = upstream.read(MAX_BODY+1)
                        if len(data) > MAX_BODY:
                            raise BudgetError('The reply exceeds the local limit.', 'invalid_stream')
                        reply = json.loads(data)
                        for choice in reply.get('choices', []):
                            chat_session.text += choice.get('message', {}).get('content') or ''
                            chat_session.reason = choice.get('finish_reason') or chat_session.reason
                        self.wfile.write(data)
                    return
                # read1 preserves incremental SSE delivery; read(n) can wait for
                # a full buffer and make a working model appear unresponsive.
                while True:
                    chunk = upstream.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except BudgetError as exc:
                self.close_connection = True
                if not response_started:
                    self.reply_json(422, {'error': {'message': str(exc), 'code': exc.code, 'details': exc.details}})
                else:
                    self.wfile.write(guarded_stream.frame({'error': {'message': str(exc), 'code': exc.code}}))
                    self.wfile.write(b'data: [DONE]\n\n')
                    self.wfile.flush()
            except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                self.close_connection = True
                if not response_started:
                    self.reply_json(400, {'error': 'Invalid request or local profile. Reload the launcher settings.'})
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True
            except OSError:
                self.close_connection = True
                if not response_started:
                    self.reply_json(502, {'error': 'The selected local model server is unavailable. Start its backend and try again.'})
            finally:
                if chat_session:
                    chat_session.close()
                if connection:
                    connection.close()

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.daemon_threads = True
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['state', 'save', 'select', 'prepare', 'diagnose', 'serve','models','model-status','memory-list','memory-save','memory-archive','memory-preview','handoff','updates','track-update-source','plugins','plugin-approve','chat','training-preflight','training-start','training-status','training-stop','training-latest'])
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        config = core.load_config(args.config)
        if args.action == 'serve':
            core.ensure_state(config)
            with make_server(config) as server:
                server.serve_forever()
            return
        payload = json.loads(sys.stdin.buffer.read().decode('utf-8-sig') or '{}') if args.action in ('save', 'select','models','memory-list','memory-save','memory-archive','memory-preview','updates','track-update-source','plugin-approve','chat','training-preflight','training-start','training-status','training-stop','training-latest') else {}
        profile = lambda: core.get_profile(core.ensure_state(config))
        if args.action=='chat':
            chosen=core.get_profile(core.ensure_state(config),payload.get('profileId'))
            local_chat.stream(config,chosen,payload)
            return
        if args.action.startswith('training-'):
            chosen=core.get_profile(core.ensure_state(config),payload.get('profileId'))
            operations={'training-preflight':lambda:training_local.preflight(config,chosen),
                        'training-start':lambda:training_local.start(config,chosen),
                        'training-status':lambda:training_local.status(config,chosen,payload.get('jobId')),
                        'training-stop':lambda:training_local.stop(config,chosen,payload.get('jobId')),
                        'training-latest':lambda:training_local.latest(config,chosen)}
            print(json.dumps(operations[args.action](),ensure_ascii=True));return
        operations = {'state': lambda: core.view_state(config), 'save': lambda: core.save_profile(config, payload),
                      'select': lambda: core.select_profile(config, payload), 'prepare': lambda: core.prepare_clients(config),
                      'diagnose': lambda: core.diagnose(config),'models':lambda:backends.discover(config,payload),
                      'model-status':lambda:backends.status(config,profile()),
                      'memory-list':lambda:dict(items=memory.items(config,profile(),payload.get('query',''),payload.get('archived',False))),
                      'memory-save':lambda:memory.save(config,profile(),payload),
                      'memory-archive':lambda:memory.archive(config,profile(),payload),
                      'memory-preview':lambda:memory.recall(config,{**profile(),'useMemory':True},payload.get('query','')),
                      'handoff':lambda:memory.handoff(config,profile()),
                      'updates':lambda:update_center.check(config,core.VERSION,payload.get('includePrereleases',True)),
                      'track-update-source':lambda:update_center.save_model_source(config,payload)}
        operations['plugins']=lambda:dict(apiVersion=plugin_host.API_VERSION,items=plugin_host.inventory(config))
        operations['plugin-approve']=lambda:plugin_host.approve(config,payload)
        print(json.dumps(operations[args.action](), ensure_ascii=True))
    except Exception as exc:
        # Known validation messages are actionable; filesystem/network exceptions
        # can contain private paths, so do not send their details to the GUI.
        message = str(exc) if isinstance(exc, ValueError) else 'The local operation failed. Check installation paths and available disk space.'
        print(json.dumps({'error': message}), file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
