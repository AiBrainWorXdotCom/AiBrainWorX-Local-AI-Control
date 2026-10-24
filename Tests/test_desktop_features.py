"""Contracts for local backends, memory, update checking and tool-free chat."""
import base64
from contextlib import contextmanager, redirect_stdout
import copy
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
import control_core as core
import control_runtime as runtime
import model_backends as backends
import project_memory as memory
import app_updates as updates
import local_chat


@contextmanager
def server(handler):
    srv=ThreadingHTTPServer(('127.0.0.1',0),handler);srv.daemon_threads=True
    thread=threading.Thread(target=srv.serve_forever,daemon=True);thread.start()
    try:yield srv
    finally:srv.shutdown();srv.server_close();thread.join(3)


class Features(unittest.TestCase):
    def test_library_keeps_attribution_and_separates_research(self):
        root=Path(__file__).resolve().parents[1]/'app'
        suggestions=json.loads((root/'model-suggestions.json').read_text(encoding='utf-8'))
        details=json.loads((root/'model-details.json').read_text(encoding='utf-8'))
        indexed={m['id']:m for m in details}
        self.assertEqual(len(indexed),len(details))
        for m in suggestions:
            self.assertIn(m['license'],('mit','apache-2.0'))
            detail=indexed[m['id']]
            self.assertTrue(detail['launcher'])
            self.assertEqual(detail['creator'],m['creator'])
            self.assertEqual(detail['source'],m['modelCard'])
            self.assertEqual(m['detailsUrl'],'https://aibrainworx.com/model-library/'+detail['slug']+'/')
            self.assertTrue(detail['summary'] and detail['localNote'] and detail['revision'])
        research=indexed['deepseek-ai/DeepSeek-V4.1-Flash-1017']
        self.assertFalse(research['launcher'])
        self.assertNotIn(research['id'],{m['id'] for m in suggestions})

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.workspace=self.root/'project';self.workspace.mkdir()
        model=self.root/'strata-test.json';model.write_text('{"model_name":"test-model"}')
        self.config=dict(StateRoot=str(self.root/'runtime'),WorkspaceRoot=str(self.workspace),StrataConfig=str(model),PythonExecutable=sys.executable,HarnessEntry=__file__)
        self.profile=core.default_profile(self.config)
        self.ports=patch.object(core,'port_open',return_value=False);self.ports.start()

    def tearDown(self):
        self.ports.stop();self.temp.cleanup()

    def save_profile(self,profile,new=False):
        state=core.ensure_state(self.config)
        return core.save_profile(self.config,dict(profile=profile,revision=state['revision'],saveAsNew=new))

    def test_loopback_only_and_no_gateway_loop(self):
        userinfo='user'+':placeholder'
        for url in ['https://api.example.com/v1','http://127.0.0.1:8082/v1','http://'+userinfo+'@127.0.0.1:1234/v1','http://127.0.0.1:1234/other','http://127.0.0.1:1234/v1?x=1','http://127.0.0.1.example.com:1234/v1']:
            with self.assertRaises(ValueError):backends.local_url(url)
        self.assertEqual(backends.local_url('http://localhost:1234/'),'http://127.0.0.1:1234/v1')

    def test_external_only_setup_does_not_require_strata(self):
        config=dict(self.config,ModelBackend='ollama',ModelId='local:4b',ModelBaseUrl='http://127.0.0.1:11434/v1')
        config.pop('StrataConfig')
        p=core.default_profile(config);self.assertEqual(p['model']['backend'],'ollama')
        prepared=core.prepare_clients(config)
        text=(Path(prepared['CodexHome'])/'aibrainworx-local.config.toml').read_text()
        self.assertIn('local:4b',text);self.assertNotIn('model_reasoning_effort = "medium"',text)

    def test_memory_is_project_scoped_and_shared_across_model_profiles(self):
        row=memory.save(self.config,self.profile,dict(title='Decision',body='Use local models.',kind='decision',pinned=True,verified=True))
        alternate=copy.deepcopy(self.profile);alternate['id']='other-model'
        self.assertEqual(len(memory.items(self.config,alternate)),1)
        other=self.root/'other';other.mkdir();alternate['workspaceRoot']=str(other)
        self.assertEqual(memory.items(self.config,alternate),[])
        with self.assertRaises(ValueError):memory.save(self.config,alternate,dict(id=row['id'],title='x',body='x',kind='fact'))

    def test_memory_archive_conflict_and_bounded_recall(self):
        record=memory.save(self.config,self.profile,dict(title='Owner decision',body='A'*3900,kind='decision',pinned=True))
        for n in range(7):memory.save(self.config,self.profile,dict(title=str(n),body='B'*2000,kind='task'))
        enabled=dict(self.profile,useMemory=True)
        recalled=memory.recall(self.config,enabled,'Owner')
        self.assertLessEqual(recalled['characters'],4200);self.assertIn('Owner decision',recalled['text'])
        self.assertEqual(memory.recall(self.config,self.profile)['text'],'')
        with self.assertRaises(ValueError):memory.save(self.config,self.profile,dict(id=record['id'],updated='stale',title='bad',body='bad',kind='fact'))
        memory.archive(self.config,self.profile,dict(id=record['id']))
        self.assertNotIn('Owner decision',memory.recall(self.config,enabled)['text'])
        memory.archive(self.config,self.profile,dict(id=record['id'],restore=True))
        self.assertIn('Owner decision',memory.recall(self.config,enabled)['text'])
        handoff=memory.handoff(self.config,self.profile)['markdown']
        self.assertIn('Owner decision',handoff);self.assertNotIn(str(self.workspace),handoff)

    def test_memory_preserves_native_instructions_in_both_protocols(self):
        p=dict(self.profile,useMemory=True)
        memory.save(self.config,p,dict(title='Constraint',body='Keep the save format.',kind='fact'))
        recall=memory.recall(self.config,p)['text']
        original={'messages':[{'role':'system','content':'Native instructions'},{'role':'user','content':'hello'}],'tools':[{'type':'function','function':{'name':'inspect'}}]}
        request=core.transform_request(original,p,'/v1/chat/completions',recall)
        self.assertIn('Native instructions',request['messages'][0]['content']);self.assertIn('Keep the save format',request['messages'][0]['content'])
        self.assertEqual(request['tools'],original['tools']);self.assertNotIn('memory',original['messages'][0]['content'])
        response=core.transform_request({'instructions':'Native','input':'hello'},p,'/v1/responses',recall)
        self.assertTrue(response['instructions'].startswith('Native'))

    def test_profile_routing_auth_and_model_mismatch(self):
        calls=[]
        class Backend(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                calls.append((self.server.server_port,self.headers.get('Authorization'),body))
                raw=b'{"ok":true}';self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
        with server(Backend) as first,server(Backend) as second:
            identities=[]
            for n,target in enumerate((first,second)):
                p=copy.deepcopy(self.profile);p['name']='Backend '+str(n)
                p['model']=dict(backend='lmstudio',baseUrl=f'http://127.0.0.1:{target.server_port}/v1',modelId='model-'+str(n),contextWindow=8192,configPath='',apiKeyEnv='AWX_TEST_KEY',vision=False,reasoningEffort='')
                identities.append(self.save_profile(p,new=True)['activeId'])
            with runtime.make_server(self.config,0) as gateway,patch.dict(os.environ,{'AWX_TEST_KEY':'unit-test-token'}):
                thread=threading.Thread(target=gateway.serve_forever,daemon=True);thread.start()
                try:
                    for n,identity in enumerate(identities):
                        conn=HTTPConnection('127.0.0.1',gateway.server_port,timeout=3)
                        conn.request('POST',f'/profiles/{identity}/v1/chat/completions',json.dumps({'model':'model-'+str(n),'messages':[]}),{'Content-Type':'application/json','Authorization':'unrelated-client-value'})
                        reply=conn.getresponse();self.assertEqual(reply.status,200);reply.read();conn.close()
                    conn=HTTPConnection('127.0.0.1',gateway.server_port,timeout=3)
                    conn.request('POST',f'/profiles/{identities[0]}/v1/chat/completions',json.dumps({'model':'wrong-model','messages':[]}),{'Content-Type':'application/json'})
                    reply=conn.getresponse();self.assertEqual(reply.status,409);reply.read();conn.close()
                finally:gateway.shutdown();thread.join(3)
        self.assertEqual([r[0] for r in calls],[first.server_port,second.server_port])
        self.assertTrue(all(r[1]=='Bearer unit-test-token' for r in calls))

    def test_ollama_inventory_excludes_cloud_models_and_redirects(self):
        class Inventory(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):
                data=json.dumps({'models':[{'name':'local:4b'},{'name':'remote:cloud','remote_host':'https://example.com'}]}).encode()
                self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        with server(Inventory) as target:
            found=backends.discover(self.config,dict(backend='ollama',baseUrl=f'http://127.0.0.1:{target.server_port}/v1'))
            self.assertEqual([x['modelId'] for x in found['models']],['local:4b'])

    def test_update_checks_do_not_claim_success_on_error(self):
        encoded=base64.b64encode(b'0.3.0-alpha.1').decode()
        with patch.object(updates,'request_json',side_effect=[[],{'content':encoded}]):
            result=updates.check('0.2.0-alpha.1');self.assertEqual(result['state'],'available');self.assertEqual(result['channel'],'main source package')
        with patch.object(updates,'request_json',side_effect=OSError):self.assertEqual(updates.check('0.3.0-alpha.1')['state'],'unavailable')
        self.assertGreater(updates.version_key('0.3.0'),updates.version_key('0.3.0-rc.2'))
        self.assertGreater(updates.version_key('0.3.0-alpha.10'),updates.version_key('0.3.0-alpha.2'))

    def test_tool_free_chat_reads_incremental_unicode_sse(self):
        seen=[]
        class Stream(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                seen.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
                for text in ['Hello ','world!']:
                    self.wfile.write(('data: '+json.dumps({'choices':[{'delta':{'content':text}}]})+'\n\n').encode());self.wfile.flush()
                self.wfile.write(b'data: [DONE]\n\n')
        with server(Stream) as target,redirect_stdout(io.StringIO()) as output:
            local_chat.stream(self.config,self.profile,{'messages':[{'role':'user','content':'hello'}]},target.server_port)
        rows=[json.loads(s) for s in output.getvalue().splitlines()]
        self.assertEqual(rows[-1]['content'],'Hello world!');self.assertNotIn('tools',seen[0])


if __name__=='__main__':unittest.main()
