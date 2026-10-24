"""Local model discovery and transport settings; never starts or downloads models."""
from __future__ import annotations

from copy import deepcopy
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit

DEFAULT_URLS = {'strata': 'http://127.0.0.1:8081/v1', 'ollama': 'http://127.0.0.1:11434/v1', 'lmstudio': 'http://127.0.0.1:1234/v1', 'compatible':'http://127.0.0.1:8080/v1'}


def local_url(value):
    if not isinstance(value, str) or any(ord(c) < 33 for c in value):
        raise ValueError('Enter a local HTTP API URL.')
    try:
        parsed = urlsplit(value.rstrip('/'))
        port = parsed.port or 80
    except ValueError:
        raise ValueError('The API port is invalid.') from None
    if (parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost')
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ('', '/v1') or not 1 <= port <= 65535 or port == 8082):
        raise ValueError('Use http://127.0.0.1:PORT/v1 on this PC; port 8082 is reserved for the launcher.')
    return f'http://127.0.0.1:{port}/v1'


def model_name(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 240 or any(ord(c) < 32 for c in value):
        raise ValueError('Choose a valid model identifier from the local server.')
    return value.strip()


def strata_model(path):
    path = Path(path)
    if not path.is_absolute() or path.suffix.lower() != '.json' or not path.is_file():
        raise ValueError('Choose an installed Strata JSON configuration.')
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    name = model_name(data.get('model_name'))
    aliases = [model_name(x) for x in data.get('aliases', []) if isinstance(x, str)]
    if data.get('api_key') or data.get('host', '127.0.0.1') not in ('127.0.0.1', 'localhost') or data.get('port', 8081) != 8081:
        raise ValueError('This Strata controller requires loopback port 8081 without an API key.')
    context = 16384
    args = data.get('args', [])
    for flag in ('--max-context', '--ctx-size', '-c'):
        if isinstance(args, list) and flag in args:
            try:
                context = int(args[args.index(flag) + 1])
            except (ValueError, IndexError, TypeError):
                pass
            break
    return dict(backend='strata', baseUrl=DEFAULT_URLS['strata'], modelId=aliases[0] if aliases else name,
                configPath=str(path.resolve()), contextWindow=context, apiKeyEnv='', vision=False,
                reasoningEffort='', ids=[name, *aliases])


def default_model(config):
    if config.get('ModelBackend', 'strata') != 'strata':
        backend = config['ModelBackend']
        return dict(backend=backend, baseUrl=config.get('ModelBaseUrl', DEFAULT_URLS[backend]),
                    modelId=config.get('ModelId', ''), configPath='', contextWindow=16384,
                    apiKeyEnv='', vision=False, reasoningEffort='')
    return strata_model(config['StrataConfig'])


def normalize(value, config, validate_file=True):
    model = deepcopy(value if isinstance(value, dict) else default_model(config))
    backend = model.get('backend')
    if backend not in DEFAULT_URLS:
        raise ValueError('Choose Strata, Ollama, LM Studio or another local compatible server.')
    model['baseUrl'] = local_url(model.get('baseUrl', DEFAULT_URLS[backend]))
    model['modelId'] = model_name(model.get('modelId'))
    context = model.get('contextWindow', 16384)
    if type(context) is not int or not 4096 <= context <= 1048576:
        raise ValueError('Context must be 4096–1048576 tokens and match the server configuration.')
    model['contextWindow'] = context
    key = model.get('apiKeyEnv', '')
    if not isinstance(key, str) or key and not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,63}', key):
        raise ValueError('Use an environment variable name for an optional API key.')
    model['apiKeyEnv'] = key
    if type(model.get('vision', False)) is not bool:
        raise ValueError('Invalid vision setting.')
    model.setdefault('vision', False)
    if model.get('reasoningEffort', '') not in ('', 'none', 'low', 'medium', 'high', 'xhigh'):
        raise ValueError('Invalid reasoning setting.')
    model.setdefault('reasoningEffort', '')
    if backend == 'ollama' and ('cloud' in model['modelId'].lower().split(':')[-1] or model.get('remoteHost')):
        raise ValueError('Cloud-routed Ollama models are not supported by this local-only connector.')
    if backend == 'strata':
        model['baseUrl'] = DEFAULT_URLS['strata']
        if validate_file:
            installed = strata_model(model.get('configPath', config.get('StrataConfig', '')))
            if model['modelId'] not in installed['ids']:
                raise ValueError('The model ID does not belong to the selected Strata config.')
            model['configPath'] = installed['configPath']
    else:
        model['configPath'] = ''
    return model


def headers(model):
    name = model.get('apiKeyEnv', '')
    if name:
        value = os.environ.get(name)
        if not value or '\r' in value or '\n' in value:
            raise ValueError('The API-key environment variable is missing. Set it before starting the settings service.')
        return {'Authorization': 'Bearer ' + value}
    return {}


def get_json(model, route, timeout=2):
    url = urlsplit(local_url(model['baseUrl']))
    conn = HTTPConnection('127.0.0.1', url.port, timeout=timeout)
    try:
        conn.request('GET', route, headers=headers(model))
        response = conn.getresponse()
        if response.status != 200:
            raise ValueError('The local API did not respond successfully. Check its server and authentication settings.')
        data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024:
            raise ValueError('The local API returned too much metadata.')
        return json.loads(data)
    finally:
        conn.close()


def discover(config, request):
    backend = request.get('backend', 'strata')
    if backend not in DEFAULT_URLS:
        raise ValueError('Choose an available backend.')
    if backend == 'strata':
        paths = []
        if config.get('StrataRoot'):
            paths += list(Path(config['StrataRoot']).glob('strata-*.json'))
        for path in (request.get('configPath'), config.get('StrataConfig')):
            if path:
                paths.append(Path(path))
        models = []
        for path in dict.fromkeys(paths):
            try:
                model = strata_model(path)
                model['label'] = model['modelId']
                models.append(model)
            except (OSError, ValueError, TypeError):
                continue
        return dict(models=models, note='Installed Strata configurations. No download or model start was performed.')
    url = local_url(request.get('baseUrl', DEFAULT_URLS[backend]))
    model = dict(baseUrl=url, apiKeyEnv=request.get('apiKeyEnv', ''))
    response = get_json(model, '/api/tags' if backend == 'ollama' else '/v1/models')
    entries = response.get('models', []) if backend == 'ollama' else response.get('data', [])
    models = []
    for entry in entries[:250]:
        name = entry.get('name') if backend == 'ollama' else entry.get('id')
        if not isinstance(name, str) or entry.get('remote_host') or 'cloud' in name.lower().split(':')[-1]:
            continue
        models.append(dict(backend=backend, baseUrl=url, modelId=model_name(name), label=name, configPath='',
                           contextWindow=16384, apiKeyEnv=model['apiKeyEnv'], vision=False, reasoningEffort=''))
    return dict(models=models, note='Local server inventory. Verify context and tool support for your chosen model; no inference request was sent.')


def status(config, profile):
    model = normalize(profile.get('model'), config, validate_file=False)
    try:
        if model['backend'] == 'strata':
            health = get_json(model, '/health')
            ids = strata_model(model['configPath'])['ids']
            ready = health.get('service') == 'strata' and health.get('loaded') and health.get('model') in ids
            detail = 'Ready on this PC.' if ready else 'Selected Strata model is not loaded. Stop the existing model before changing models.'
        else:
            available = discover(config, model)['models']
            ready = any(m['modelId'] == model['modelId'] for m in available)
            detail = 'Available from the local server; it may load on the first request.' if ready else 'Selected model is not in the local server inventory.'
        return dict(ready=bool(ready), backend=model['backend'], modelId=model['modelId'], detail=detail)
    except (OSError, ValueError, TypeError):
        return dict(ready=False, backend=model['backend'], modelId=model['modelId'], detail='Local server unavailable. Start it and refresh the model list.')
