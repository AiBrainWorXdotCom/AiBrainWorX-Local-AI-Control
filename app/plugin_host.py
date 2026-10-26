"""Versioned, opt-in user plugins outside the app installation.

These are trusted local programs, NOT a security sandbox. Capability declarations
are consent information, not OS-enforced restrictions. No plugin auto-installs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

import control_core as core

API_VERSION = 1
HOOKS = {'chat.before_send', 'chat.after_reply'}
CAPABILITIES = {'read_chat', 'modify_chat', 'local_files', 'network', 'audio_capture', 'audio_playback'}
PLUGIN_ID = re.compile(r'^[a-z][a-z0-9-]{1,63}$')


def home(config):
    return Path(config['StateRoot']) / 'plugins'


def inspect(config, directory):
    directory = Path(directory)
    if directory.is_symlink() or (hasattr(directory, 'is_junction') and directory.is_junction()):
        raise ValueError('Plugin links are not loaded.')
    manifest = directory/'plugin.json'
    if not manifest.is_file() or manifest.stat().st_size > 65536:
        raise ValueError('A small plugin.json manifest is required.')
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    identity = data.get('id', '')
    if not PLUGIN_ID.fullmatch(identity) or directory.name != identity:
        raise ValueError('Plugin ID must match its folder name.')
    api = data.get('apiVersion')
    if type(api) is not int:
        raise ValueError('Plugin API version is required.')
    hooks, permissions = data.get('hooks', []), data.get('capabilities', [])
    if not isinstance(hooks, list) or set(hooks)-HOOKS or not isinstance(permissions, list) or set(permissions)-CAPABILITIES:
        raise ValueError('Unsupported plugin hooks or declared capabilities.')
    runtime, entry = data.get('runtime'), data.get('entry', '')
    if runtime not in ('python', 'node') or not isinstance(entry, str):
        raise ValueError('Choose a Python or Node plugin entry.')
    relative = Path(entry)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Plugin entry must stay in its folder.')
    target = directory/relative
    if not target.is_file() or not target.resolve().is_relative_to(directory.resolve()):
        raise ValueError('Plugin entry is missing or outside its folder.')
    fingerprint = hashlib.sha256()
    files, size = 0, 0
    for path in sorted(directory.rglob('*')):
        if any(part in ('node_modules', '.venv', '__pycache__', '.git') for part in path.relative_to(directory).parts):
            continue
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            raise ValueError('Linked plugin files are not loaded.')
        if path.is_file():
            files += 1; size += path.stat().st_size
            if files > 100 or size > 2*1024*1024:
                raise ValueError('Plugin source exceeds the review limit.')
            fingerprint.update(path.relative_to(directory).as_posix().encode()+b'\0'+path.read_bytes())
    return {**data, 'fingerprint': fingerprint.hexdigest(), 'compatible': api == API_VERSION,
            '_directory': str(directory), '_entry': str(target)}


def approvals(config):
    path = Path(config['StateRoot'])/'plugin-approvals.local.json'
    return core.read_json(path) if path.is_file() else {}


def inventory(config):
    result, saved = [], approvals(config)
    if not home(config).is_dir():
        return []
    for directory in sorted(home(config).iterdir())[:100]:
        if not directory.is_dir():
            continue
        try:
            plugin = inspect(config, directory)
            approved = saved.get(plugin['id'], {})
            enabled = plugin['compatible'] and approved.get('enabled') is True and approved.get('fingerprint') == plugin['fingerprint']
            state = 'enabled' if enabled else 'incompatible' if not plugin['compatible'] else 'review'
            result.append({k: v for k, v in plugin.items() if not k.startswith('_')} | {'state': state})
        except (OSError, ValueError, TypeError):
            result.append({'id': directory.name, 'name': directory.name, 'state': 'invalid',
                           'detail': 'Invalid or unsupported manifest. Files were left intact.'})
    return result


def approve(config, payload):
    identity = payload.get('id', '')
    if not PLUGIN_ID.fullmatch(identity):
        raise ValueError('Choose a valid local plugin.')
    plugin = inspect(config, home(config)/identity)
    if plugin['fingerprint'] != payload.get('fingerprint'):
        raise ValueError('Plugin changed since review. Inspect it again.')
    enabled = payload.get('enabled') is True
    if enabled and (not plugin['compatible'] or payload.get('acceptLocalCodeRisk') is not True):
        raise ValueError('A compatible plugin needs explicit approval to run local code with your account permissions.')
    with core.state_lock(config):
        saved = approvals(config)
        saved[identity] = {'enabled': enabled, 'fingerprint': plugin['fingerprint']}
        core.write_json(Path(config['StateRoot'])/'plugin-approvals.local.json', saved)
    return {'note': 'Plugin enabled.' if enabled else 'Plugin disabled; its files were preserved.'}


def run_hook(config, hook, data):
    if hook not in HOOKS:
        raise ValueError('Unknown plugin hook.')
    current = data
    for public in inventory(config):
        if public['state'] != 'enabled' or hook not in public.get('hooks', []):
            continue
        plugin = inspect(config, home(config)/public['id'])
        # A second fingerprint check closes the ordinary edit-between-review/use
        # case; this is still trusted code, not hostile-code isolation.
        if plugin['fingerprint'] != public['fingerprint']:
            raise ValueError('Plugin changed before execution.')
        runtime = config.get('PythonExecutable') if plugin['runtime'] == 'python' else config.get('NodeExecutable')
        if not runtime or not Path(runtime).is_file():
            raise ValueError('The approved plugin runtime is unavailable.')
        encoded = json.dumps({'apiVersion': API_VERSION, 'hook': hook, 'data': current})
        if len(encoded.encode()) > 1024*1024:
            raise ValueError('Plugin input is too large.')
        data_directory = Path(config['StateRoot'])/'plugin-data'/plugin['id']
        data_directory.mkdir(parents=True, exist_ok=True)
        environment = {**os.environ, 'AIBRAINWORX_PLUGIN_DATA': str(data_directory)}
        result = subprocess.run([runtime, plugin['_entry']], input=encoded, text=True,
                                encoding='utf-8', capture_output=True, timeout=3, check=True,
                                cwd=plugin['_directory'], env=environment, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if len(result.stdout.encode()) > 1024*1024:
            raise ValueError('Plugin output is too large.')
        reply = json.loads(result.stdout)
        if not isinstance(reply, dict) or reply.get('apiVersion') != API_VERSION or not isinstance(reply.get('data'), dict):
            raise ValueError('Plugin returned an invalid response.')
        if hook == 'chat.before_send' and 'modify_chat' not in plugin['capabilities'] and reply['data'] != current:
            raise ValueError('This plugin was not approved to modify chat.')
        current = reply['data']
    return current
