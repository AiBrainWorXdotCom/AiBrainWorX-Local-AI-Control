"""Token-count worker using the owner's installed Strata frontend; no engine starts.

The upstream code stays in its installation and retains its own license. This
adapter imports it rather than bundling a fork or downloading a tokenizer.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    root, cfg_path = Path(args.root).resolve(), Path(args.config).resolve()
    sys.path[:0] = [str(root), str(root / 'tools')]
    from serve import server
    import strata_tokenizer as ST
    cfg = json.loads(cfg_path.read_text(encoding='utf-8-sig'))
    folder = Path(cfg['tokenizer'])
    vocab = json.loads((folder / 'vocab.json').read_text(encoding='utf-8'))
    tokens = [None] * len(vocab)
    for token, index in vocab.items():
        tokens[index] = token
    types = json.loads((folder / 'token_type.json').read_text())
    merges = (folder / 'merges.txt').read_text(encoding='utf-8').split('\n')
    options = json.loads((folder / 'tokenizer.json').read_text(encoding='utf-8'))
    tokenizer = ST.Tokenizer(tokens, merges, types, options.get('pre') or 'qwen35', options.get('special_ids') or None)
    template = server.ChatTemplate(folder / 'chat_template.jinja')
    service = server.Service(object(), tokenizer, template, cfg['model_name'])
    service.effort_end = cfg.get('effort_position') == 'end'
    service.config_effort = cfg.get('reasoning_effort')
    digest = hashlib.sha256(template.source.encode()).hexdigest()
    for line in sys.stdin:
        try:
            item = json.loads(line)
            if item.get('template_sha256') != digest:
                raise ValueError('The running server template differs from the installed tokenizer.')
            shared = cfg_path.with_suffix('')
            shared = Path(str(shared) + '.shared-settings.json')
            service.shared = server.clean_shared_defaults(json.loads(shared.read_text(encoding='utf-8'))) if shared.exists() else {}
            req = item['payload']
            responses = item.get('route') == '/v1/responses'
            if not responses:
                req = service.with_shared(req, 'openai')
            if req.get('strata_mcp'):
                raise ValueError('Server-added MCP tools require a server-native counting endpoint.')
            if responses:
                api = server.responses_api
                api.check_request(req)
                messages = api.input_messages(req)
                tools, _, _ = api.request_tools(req)
                kwargs = api.template_kwargs(req, {'reasoning_effort': service.effort_default()})
                fmt = api.text_format(req)
            else:
                messages, tools, kwargs = server.openai_to_messages(req)
                fmt = req.get('response_format')
            # Vision embeddings and forced call prefixes are not ordinary text.
            if any(isinstance(m.get('content'), list) and any(p.get('type') not in ('text', 'input_text') for p in m['content']) for m in messages):
                raise ValueError('Image requests need native multimodal token budgeting.')
            if server.tool_choice_of(req.get('tool_choice'))[0] == 'none':
                tools = None
            messages, _ = server.prepare_format(fmt, messages, with_tools=bool(tools))
            count = len(service.encode_prompt(messages, tools, kwargs, store=True))
            forced = server.forced_call(req.get('tool_choice'), tools) if not responses else None
            if forced:
                # A forced-call prefix is short, but count its actual encoded
                # bytes as extra rather than presuming zero cost.
                prefix = service.force_text(forced)
                if prefix:
                    count += len(tokenizer.encode(prefix, parse_special=True))
            print(json.dumps({'count': count}), flush=True)
        except Exception:
            # Imported-library exceptions can contain input text or personal paths.
            print(json.dumps({'error': 'Cannot count this request with the installed Strata frontend.'}), flush=True)


if __name__ == '__main__':
    main()
