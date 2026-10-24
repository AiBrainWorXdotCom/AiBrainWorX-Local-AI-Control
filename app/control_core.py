"""Local profiles, managed client configuration and read-only diagnostics."""
from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import socket
import subprocess
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
PROFILE_ID = re.compile(r'^[a-zA-Z0-9-]{1,64}$')
MAX_PROMPT = 8192


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def load_config(path):
    config = read_json(path)
    for field in ('StateRoot', 'WorkspaceRoot'):
        if not isinstance(config.get(field), str) or not Path(config[field]).is_absolute():
            raise ValueError('Run Setup.cmd to configure this PC.')
    return config


def state_path(config):
    return Path(config['StateRoot']) / 'launch-profiles.local.json'


def data_identity(config):
    return hashlib.sha256(str(Path(config['StateRoot']).resolve()).casefold().encode()).hexdigest()[:24]


@contextmanager
def state_lock(config):
    path = state_path(config).with_suffix('.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as handle:
        if handle.tell() == 0:
            handle.write(b'0')
            handle.flush()
        deadline = time.monotonic() + 5
        while True:
            try:
                handle.seek(0)
                if os.name == 'nt':
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise ValueError('Settings are busy in another window. Try again.')
                time.sleep(.05)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def presets():
    return read_json(ROOT / 'app/prompt-presets.json')


def default_profile(config):
    return dict(id='default', name='Default project', workspaceRoot=config['WorkspaceRoot'],
                enginePython=config.get('EnginePython', ''), unrealProjectName=config.get('UnrealProjectName', ''),
                preset='general', useInstructions=False, instructions=presets()[0]['text'],
                overrideSampling=False, temperature=.7, topP=.9, maxOutputTokens=4096)


def ensure_state(config):
    if not state_path(config).exists():
        with state_lock(config):
            if not state_path(config).exists():
                write_json(state_path(config), dict(schemaVersion=1, revision=0, activeId='default', profiles=[default_profile(config)]))
    state = read_json(state_path(config))
    if state.get('schemaVersion') != 1 or not state.get('profiles'):
        raise ValueError('The local profiles file is invalid. Restore its backup or run Setup.')
    return state


def get_profile(state, identity=None):
    identity = identity or state['activeId']
    if not isinstance(identity, str) or not PROFILE_ID.fullmatch(identity):
        raise ValueError('Invalid profile identifier.')
    for profile in state['profiles']:
        if profile['id'] == identity:
            return profile
    raise ValueError('The selected profile no longer exists. Reload the launcher.')


def port_open(port):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=.15):
            return True
    except OSError:
        return False


def validate_profile(value):
    value = deepcopy(value)
    if not PROFILE_ID.fullmatch(str(value.get('id', ''))):
        raise ValueError('Invalid profile identifier.')
    name = value.get('name', '').strip()
    if not name or len(name) > 64 or any(ord(c) < 32 for c in name):
        raise ValueError('Use a profile name with 1–64 printable characters.')
    value['name'] = name
    for field in ('workspaceRoot', 'enginePython'):
        path = value.get(field, '')
        if not isinstance(path, str) or any(c in path for c in ('\x00', '\r', '\n', '"')):
            raise ValueError('Choose a valid folder.')
        if field == 'workspaceRoot' or path:
            if not Path(path).is_absolute() or not Path(path).is_dir():
                raise ValueError('Choose an existing folder on this PC.')
            value[field] = str(Path(path).resolve())
    if value['enginePython'] and not (Path(value['enginePython']) / 'remote_execution.py').is_file():
        raise ValueError('The engine Python folder must contain remote_execution.py.')
    projects = list(Path(value['workspaceRoot']).glob('*.uproject'))
    value['unrealProjectName'] = projects[0].stem if len(projects) == 1 else ''
    for field in ('useInstructions', 'overrideSampling'):
        if type(value.get(field)) is not bool:
            raise ValueError('Invalid checkbox value.')
    text = value.get('instructions', '')
    if not isinstance(text, str) or len(text) > MAX_PROMPT or '\x00' in text:
        raise ValueError('Instructions must be text of at most 8192 characters.')
    for field, low, high in (('temperature', 0, 2), ('topP', .01, 1)):
        number = value.get(field)
        if type(number) not in (int, float) or not math.isfinite(number) or not low <= number <= high:
            raise ValueError('Sampling values are outside the supported range.')
    cap = value.get('maxOutputTokens')
    if type(cap) is not int or not 64 <= cap <= 8192:
        raise ValueError('The output cap must be between 64 and 8192 tokens.')
    return value


def view_state(config):
    state = ensure_state(config)
    return dict(version=VERSION, dataIdentity=data_identity(config), **state, active=get_profile(state), presets=presets())


def save_profile(config, payload):
    ensure_state(config)
    with state_lock(config):
        state = ensure_state(config)
        if payload.get('revision') != state['revision']:
            raise ValueError('Settings changed in another window. Reload before saving.')
        candidate = deepcopy(payload['profile'])
        if payload.get('saveAsNew'):
            candidate['id'] = uuid.uuid4().hex
        candidate = validate_profile(candidate)
        if any(p['name'].casefold() == candidate['name'].casefold() and p['id'] != candidate['id'] for p in state['profiles']):
            raise ValueError('That profile name is already in use.')
        old = next((p for p in state['profiles'] if p['id'] == candidate['id']), None)
        if old and old['id'] == state['activeId'] and port_open(3080) and any(old[k] != candidate[k] for k in ('workspaceRoot', 'enginePython', 'unrealProjectName')):
            raise ValueError('Stop Harness before changing the active project folders.')
        if old:
            state['profiles'][state['profiles'].index(old)] = candidate
        else:
            state['profiles'].append(candidate)
            if not port_open(3080):
                state['activeId'] = candidate['id']
        state['revision'] += 1
        write_json(state_path(config).with_suffix('.bak'), ensure_state(config))
        write_json(state_path(config), state)
    return view_state(config)


def select_profile(config, payload):
    ensure_state(config)
    with state_lock(config):
        state = ensure_state(config)
        identity = payload['id']
        get_profile(state, identity)
        if identity != state['activeId'] and port_open(3080):
            raise ValueError('Stop Harness before switching project profiles. Existing chats stay in their original home.')
        state['activeId'] = identity
        state['revision'] += 1
        write_json(state_path(config), state)
    return view_state(config)


def transform_request(body, profile, route):
    if not isinstance(body, dict):
        raise ValueError('The API request must be a JSON object.')
    result = deepcopy(body)
    if profile['overrideSampling']:
        result.update(temperature=profile['temperature'], top_p=profile['topP'])
    key = 'max_output_tokens' if route == '/v1/responses' else 'max_completion_tokens' if 'max_completion_tokens' in result else 'max_tokens'
    existing = result.get(key)
    cap = profile['maxOutputTokens']
    result[key] = min(existing, cap) if type(existing) is int and existing > 0 else cap
    if profile['useInstructions'] and profile['instructions'].strip():
        text = '\n\nLauncher custom instructions:\n' + profile['instructions']
        if route == '/v1/responses':
            previous = result.get('instructions') or ''
            if not isinstance(previous, str):
                raise ValueError('Response instructions must be text.')
            result['instructions'] = previous + text
        else:
            messages = result.get('messages')
            if not isinstance(messages, list):
                raise ValueError('Chat messages must be an array.')
            system = next((m for m in messages if isinstance(m, dict) and m.get('role') == 'system'), None)
            if system is None:
                messages.insert(0, {'role': 'system', 'content': text.strip()})
            elif isinstance(system.get('content'), str):
                system['content'] += text
            elif isinstance(system.get('content'), list):
                system['content'].append({'type': 'text', 'text': text})
            else:
                raise ValueError('The system message has an unsupported content type.')
    return result


def model_id(config):
    model = read_json(config['StrataConfig'])
    aliases = model.get('aliases') or []
    return str(aliases[0] if aliases else model['model_name'])


def prepare_clients(config):
    profile = get_profile(ensure_state(config))
    identity = profile['id']
    home = Path(config['StateRoot']) / 'managed-clients' / identity
    home.mkdir(parents=True, exist_ok=True)
    model = model_id(config)
    endpoint = f'http://127.0.0.1:8082/profiles/{identity}/v1'
    harness = home / 'harness'
    target = harness / 'profiles/web'
    write_json(target / 'package.json', {'name': 'aibrainworx-profile', 'private': True, 'dependencies': {}, 'dsh': {'profile': {'bundles': ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app']}}})
    bridge = ROOT / 'bridge/unreal_mcp.py'
    replacements = {'qwen3.8-flash-next-coder': model, 'http://127.0.0.1:8081/v1': endpoint,
                    'C:/AI/UnrealAssistant/unreal_mcp.py': bridge.as_posix(),
                    'C:/Projects/MyUnrealGame': Path(profile['workspaceRoot']).as_posix(),
                    'C:/Program Files/Epic Games/UE_5.8/Engine/Plugins/Experimental/PythonScriptPlugin/Content/Python': Path(profile['enginePython']).as_posix(),
                    'MyUnrealGame': profile['unrealProjectName'], 'apiKeyEnv: STRATA_LOCAL_TOKEN': 'apiKeyEnv: AIBRAINWORX_API_KEY'}
    patch = [
        {'id': 'llm-pi-ai', 'name': '@deepseek-ai/dsh-llm-pi-ai', 'config': {'providers': {'local_strata': {
            'apiKeyEnv': 'AIBRAINWORX_API_KEY', 'api': 'openai-completions', 'baseURL': endpoint,
            'models': [{'id': model, 'name': 'AiBrainWorX local model', 'maxTokens': 8192, 'contextWindow': 16384}]}}}},
        {'id': 'agent-default-model', 'name': '@deepseek-ai/dsh-agent-default-model', 'config': {'provider': 'local_strata', 'model': model}},
    ]
    if profile['unrealProjectName'] and profile['enginePython']:
        patch.append({'id': 'mcp-unreal-local', 'name': '@deepseek-ai/dsh-mcp-client', 'config': {
            'serverName': 'unreal_local', 'transport': 'stdio', 'command': config['PythonExecutable'],
            'args': [str(bridge)], 'env': {'UE_PROJECT_ROOT': profile['workspaceRoot'],
            'UE_PROJECT_NAME': profile['unrealProjectName'], 'UE_ENGINE_PYTHON': profile['enginePython']},
            'toolCallTimeoutMs': 30000}})
    # JSON is a YAML subset, so paths and prompt text need no YAML interpolation.
    write_json(target / 'cordis.patch.yml', patch)
    codex = home / 'codex'
    catalog = read_json(ROOT / 'examples/model-catalog.json')
    catalog['models'][0].update(slug=model, display_name='AiBrainWorX local model')
    write_json(codex / 'model-catalog.json', catalog)
    template = (ROOT / 'examples/dronekilla-local.config.toml').read_text(encoding='utf-8')
    if not (profile['unrealProjectName'] and profile['enginePython']):
        template = template.split('[mcp_servers.unreal_local]')[0]
    replacements['C:/AI/UnrealAssistant/model-catalog.json'] = (codex / 'model-catalog.json').as_posix()
    for before, after in replacements.items():
        if before.startswith('apiKeyEnv:'):
            continue
        template = template.replace(json.dumps(before), json.dumps(after))
    template = template.replace('command = "python"', 'command = ' + json.dumps(config['PythonExecutable'].replace('\\', '/')))
    (codex / 'aibrainworx-local.config.toml').write_text(template, encoding='utf-8')
    return dict(ProfileId=identity, HarnessHome=str(harness), CodexHome=str(codex), WorkspaceRoot=profile['workspaceRoot'],
                EnginePython=profile['enginePython'], UnrealProjectName=profile['unrealProjectName'], GatewayURL=endpoint)


def fetch_json(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as reply:
        return json.load(reply)


def diagnose(config):
    state = ensure_state(config)
    profile = get_profile(state)
    checks = []
    def add(name, ok, detail):
        checks.append(dict(name=name, status='Ready' if ok else 'Needs attention', detail=detail))
    add('Workspace', Path(profile['workspaceRoot']).is_dir(), 'Selected project folder exists.' if Path(profile['workspaceRoot']).is_dir() else 'Choose an existing project folder.')
    for name, port in (('Strata model', 8081), ('Launch settings service', 8082)):
        try:
            health = fetch_json(f'http://127.0.0.1:{port}/health')
            ok = health.get('service') == 'strata' and health.get('loaded', False) if port == 8081 else health.get('service') == 'aibrainworx-control' and health.get('dataIdentity') == data_identity(config)
            add(name, ok, 'Responding on loopback.' if ok else 'The service is still loading or belongs to another application.')
        except Exception:
            add(name, False, 'Start the model/settings service from the launcher.')
    add('Harness', Path(config['HarnessEntry']).is_file(), 'Installed client entry checked.')
    optional = config.get('CodexEntry') or str(Path(config.get('CodexCommand', '')).parent.parent / '@openai/codex/bin/codex.js')
    add('Optional terminal client', Path(optional).is_file(), 'Run Setup if the optional client is missing.')
    if profile['unrealProjectName'] and profile['enginePython']:
        env = dict(os.environ, UE_PROJECT_ROOT=profile['workspaceRoot'], UE_PROJECT_NAME=profile['unrealProjectName'], UE_ENGINE_PYTHON=profile['enginePython'])
        try:
            result = subprocess.run([config['PythonExecutable'], str(ROOT / 'bridge/unreal_mcp.py'), '--status'], env=env, capture_output=True, timeout=12, check=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            connected = json.loads(result.stdout).get('editor_connected', False)
            add('Unreal editor', connected, 'Read-only editor connection verified.' if connected else 'Open the configured project and enable loopback Python remote execution.')
        except Exception:
            add('Unreal editor', False, 'Check Python plugins, the engine Python folder and the open project.')
    else:
        checks.append(dict(name='Unreal editor', status='Optional', detail='No Unreal connection configured for this profile.'))
    return dict(version=VERSION, checks=checks, note='No generation request was sent. The report excludes prompts, credentials and personal paths.')
