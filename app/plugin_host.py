"""Versioned, opt-in user plugins outside the app installation.

These are trusted local programs, NOT a security sandbox. Capability declarations
are consent information, not OS-enforced restrictions. No plugin auto-installs.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

import control_core as core

API_VERSION = 1
HOOKS = {'chat.before_send', 'chat.after_reply', 'monitor.sample'}
CAPABILITIES = {'read_chat', 'modify_chat', 'local_files', 'network', 'audio_capture', 'audio_playback', 'read_system'}
PLUGIN_ID = re.compile(r'^[a-z][a-z0-9-]{1,63}$')
ARCHIVE_ID = re.compile(r'^(?P<id>[a-z][a-z0-9-]{1,63})-[a-f0-9]{32}$')
PANEL_STATES = {'ok', 'warning', 'error', 'unknown', 'unavailable', 'running', 'stopped', 'idle', 'generating', 'available'}


def home(config):
    return Path(config['StateRoot']) / 'plugins'


def inspect(config, directory, *, folder_id=None):
    directory = Path(directory)
    if directory.is_symlink() or (hasattr(directory, 'is_junction') and directory.is_junction()):
        raise ValueError('Plugin links are not loaded.')
    manifest = directory/'plugin.json'
    if not manifest.is_file() or manifest.stat().st_size > 65536:
        raise ValueError('A small plugin.json manifest is required.')
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict):
        raise ValueError('Plugin manifest must be a JSON object.')
    identity = data.get('id', '')
    if not PLUGIN_ID.fullmatch(identity) or (folder_id if folder_id is not None else directory.name) != identity:
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
    if relative.is_absolute() or '..' in relative.parts or ('monitor.sample' in hooks and any(part in ('node_modules', '.venv', '__pycache__', '.git') for part in relative.parts)):
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
            if not isinstance(approved, dict):
                approved = {}
            enabled = plugin['compatible'] and approved.get('enabled') is True and approved.get('fingerprint') == plugin['fingerprint']
            state = 'enabled' if enabled else 'incompatible' if not plugin['compatible'] else 'review'
            result.append({k: v for k, v in plugin.items() if not k.startswith('_')} | {'state': state})
        except (OSError, ValueError, TypeError):
            result.append({'id': directory.name, 'name': directory.name, 'state': 'invalid',
                           'detail': 'Invalid or unsupported manifest. Files were left intact.'})
    return result


def approve(config, payload):
    identity = payload.get('id', '')
    if not isinstance(identity, str) or not PLUGIN_ID.fullmatch(identity):
        raise ValueError('Choose a valid local plugin.')
    plugin = inspect(config, home(config)/identity)
    if plugin['fingerprint'] != payload.get('fingerprint'):
        raise ValueError('Plugin changed since review. Inspect it again.')
    enabled = payload.get('enabled') is True
    if enabled and (not plugin['compatible'] or payload.get('acceptLocalCodeRisk') is not True):
        raise ValueError('A compatible plugin needs explicit approval to run local code with your account permissions.')
    with core.state_lock(config):
        saved = approvals(config)
        saved[identity] = {'enabled': enabled, 'fingerprint': plugin['fingerprint'], 'revision': uuid.uuid4().hex}
        core.write_json(Path(config['StateRoot'])/'plugin-approvals.local.json', saved)
    return {'note': 'Plugin enabled.' if enabled else 'Plugin disabled; its files were preserved.'}


def _safe_plugin_location(config, root_name, child=None):
    """Resolve a move target inside the explicitly named persistent root."""
    state = Path(config['StateRoot']).resolve()
    root = Path(config['StateRoot'])/root_name
    if root.is_symlink() or (hasattr(root, 'is_junction') and root.is_junction()) or not root.resolve().is_relative_to(state):
        raise ValueError('Plugin storage must be a local directory inside StateRoot.')
    target = root/child if child is not None else root
    if target.is_symlink() or (hasattr(target, 'is_junction') and target.is_junction()) or not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Plugin location is outside its storage directory.')
    return target.resolve()


def _check_move_tree(directory):
    # Include ignored source folders too: moving a source tree must never carry
    # a junction or symbolic link to files elsewhere on this PC.
    pending, root = [directory], directory.resolve()
    while pending:
        current = pending.pop()
        if current.is_symlink() or (hasattr(current, 'is_junction') and current.is_junction()) or not current.resolve().is_relative_to(root):
            raise ValueError('Linked plugin files cannot be archived or restored.')
        if current.is_dir():
            pending.extend(current.iterdir())


def remove(config, payload):
    """Disable and archive only reviewed source; preserve all plugin data."""
    identity = payload.get('id', '')
    if not isinstance(identity, str) or not PLUGIN_ID.fullmatch(identity):
        raise ValueError('Choose a valid local plugin.')
    with core.state_lock(config):
        source = _safe_plugin_location(config, 'plugins', identity)
        plugin = inspect(config, source)
        if plugin['fingerprint'] != payload.get('fingerprint'):
            raise ValueError('Plugin changed since review. Inspect it again.')
        _check_move_tree(source)
        archive_id = identity+'-'+uuid.uuid4().hex
        destination = _safe_plugin_location(config, 'plugin-archive', archive_id)
        if destination.exists():
            raise ValueError('Archive destination already exists. Refresh and try again.')
        destination.parent.mkdir(parents=True, exist_ok=True)
        saved = approvals(config)
        saved[identity] = {'enabled': False, 'fingerprint': plugin['fingerprint'], 'revision': uuid.uuid4().hex}
        core.write_json(Path(config['StateRoot'])/'plugin-approvals.local.json', saved)
        # Both resolved absolute paths were checked against their named roots.
        shutil.move(str(source), str(destination))
    return {'note': 'Plugin disabled and archived. Its persistent data was preserved.', 'archiveId': archive_id}


def archives(config):
    root = _safe_plugin_location(config, 'plugin-archive')
    items = []
    if not root.is_dir():
        return {'items': items}
    for directory in sorted(root.iterdir())[:100]:
        match = ARCHIVE_ID.fullmatch(directory.name)
        if not match:
            continue
        try:
            plugin = inspect(config, directory, folder_id=match['id'])
            name = _text(plugin.get('name', plugin['id']), 80)
            items.append({'archiveId': directory.name, 'id': plugin['id'], 'name': name,
                          'fingerprint': plugin['fingerprint'], 'compatible': plugin['compatible']})
        except (OSError, ValueError, TypeError):
            continue
    return {'items': items}


def restore(config, payload):
    archive_id = payload.get('archiveId', '')
    match = ARCHIVE_ID.fullmatch(archive_id) if isinstance(archive_id, str) else None
    if not match:
        raise ValueError('Choose a valid archived plugin.')
    identity = match['id']
    with core.state_lock(config):
        source = _safe_plugin_location(config, 'plugin-archive', archive_id)
        destination = _safe_plugin_location(config, 'plugins', identity)
        if destination.exists():
            raise ValueError('A plugin with this ID already exists. Its files were preserved.')
        plugin = inspect(config, source, folder_id=identity)
        _check_move_tree(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        saved = approvals(config)
        saved[identity] = {'enabled': False, 'fingerprint': plugin['fingerprint'], 'revision': uuid.uuid4().hex}
        core.write_json(Path(config['StateRoot'])/'plugin-approvals.local.json', saved)
        shutil.move(str(source), str(destination))
    return {'note': 'Plugin source restored disabled. Review and explicitly enable it to run.', 'id': identity}


def run_hook(config, hook, data):
    if hook not in ('chat.before_send', 'chat.after_reply'):
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


def _number(value, minimum=0, maximum=10**18):
    if value is None:
        return None
    if type(value) not in (int, float) or not minimum <= value <= maximum or not math.isfinite(value):
        raise ValueError('Invalid monitor number.')
    return value


def _text(value, limit, *, unit=False):
    if not isinstance(value, str) or not value or len(value) > limit:
        raise ValueError('Invalid monitor text.')
    # Panels are plain text. Paths, markup and control characters have no place
    # in this schema; process rows contain a basename, never an invocation.
    if any(ord(char) < 32 or ord(char) == 127 for char in value) or any(char in value for char in '<>\\:'):
        raise ValueError('Invalid monitor text.')
    if '/' in value.replace('N/A', '') and not (unit and re.fullmatch(r'[A-Za-z%]+/[A-Za-z]+', value)):
        raise ValueError('Invalid monitor text.')
    return value


def _state(value):
    if value not in PANEL_STATES:
        raise ValueError('Invalid monitor state.')
    return value


def validate_panel(value):
    """Return only bounded data fields; never accept HTML, scripts or actions."""
    if not isinstance(value, dict) or set(value)-{'metrics', 'services', 'processes', 'note'}:
        raise ValueError('Invalid monitor panel.')
    panel = {}
    for key, limit in (('metrics', 12), ('services', 8), ('processes', 20)):
        rows = value.get(key, [])
        if not isinstance(rows, list) or len(rows) > limit:
            raise ValueError('Invalid monitor rows.')
        panel[key] = []
        for row in rows:
            if not isinstance(row, dict):
                raise ValueError('Invalid monitor row.')
            if key == 'metrics':
                if set(row)-{'label', 'value', 'unit', 'state'} or not {'label', 'value'} <= row.keys():
                    raise ValueError('Invalid monitor metric.')
                number = row['value']
                item = {'label': _text(row['label'], 64), 'value': _text(number, 64) if isinstance(number, str) else _number(number, -10**18)}
                if 'unit' in row:
                    item['unit'] = _text(row['unit'], 24, unit=True)
                if 'state' in row:
                    item['state'] = _state(row['state'])
            elif key == 'services':
                if set(row)-{'name', 'state', 'detail'} or not {'name', 'state'} <= row.keys():
                    raise ValueError('Invalid monitor service.')
                item = {'name': _text(row['name'], 64), 'state': _state(row['state'])}
                if 'detail' in row:
                    item['detail'] = _text(row['detail'], 160)
            else:
                if set(row)-{'pid', 'name', 'cpuPercent', 'memoryBytes', 'gpuMemoryBytes'} or not {'pid', 'name', 'cpuPercent', 'memoryBytes'} <= row.keys():
                    raise ValueError('Invalid monitor process.')
                if type(row['pid']) is not int or not 1 <= row['pid'] <= 2**31-1:
                    raise ValueError('Invalid monitor PID.')
                name = _text(row['name'], 64)
                if not re.fullmatch(r'[\w.()+-]+', name, flags=re.ASCII):
                    raise ValueError('Monitor process names must be basenames without arguments.')
                item = {'pid': row['pid'], 'name': name, 'cpuPercent': _number(row['cpuPercent'], 0, 100),
                        'memoryBytes': _number(row['memoryBytes'], 0, 2**63-1)}
                if 'gpuMemoryBytes' in row:
                    item['gpuMemoryBytes'] = _number(row['gpuMemoryBytes'], 0, 2**63-1)
            panel[key].append(item)
    if 'note' in value:
        panel['note'] = _text(value['note'], 500)
    return panel


def monitor_context(context):
    """Reduce caller context to existing numeric telemetry and explicit flags.

    Never forward config, chat, prompts, request identifiers or project paths.
    No monitor-side model request is necessary or performed by this host.
    """
    context = context if isinstance(context, dict) else {}
    backend = context.get('backend')
    result = {'backend': backend if backend in ('strata', 'ollama', 'lmstudio', 'compatible') else 'unknown',
              'inspectProcesses': context.get('inspectProcesses') is True,
              'includeGpuProcesses': context.get('inspectProcesses') is True and context.get('includeGpuProcesses') is True,
              'modelMetrics': None}
    metrics = context.get('modelMetrics')
    if isinstance(metrics, dict):
        safe = {}
        for section, keys in (('hardware', ('cpu', 'ram_used', 'ram_total', 'gpu_mem_used', 'gpu_mem_total')),
                              ('live', ('tok_s',))):
            original = metrics.get(section)
            if isinstance(original, dict):
                safe[section] = {key: val for key in keys if (val := original.get(key)) is None or
                                 (type(val) in (int, float) and 0 <= val <= 10**18 and math.isfinite(val))}
        live = metrics.get('live')
        if isinstance(live, dict) and isinstance(live.get('state'), str) and live['state'] in PANEL_STATES:
            safe.setdefault('live', {})['state'] = live['state']
        requests = metrics.get('requests')
        if isinstance(requests, list) and requests and isinstance(requests[0], dict):
            safe['requests'] = [{key: val for key in ('decode_tok_s', 'prompt_ms', 'prompt_read', 'first_engine_token_s', 'reused')
                                 if (val := requests[0].get(key)) is None or
                                 (type(val) in (int, float) and 0 <= val <= 10**18 and math.isfinite(val))}]
        result['modelMetrics'] = safe
    return result


def _approved_monitor(config, identity, fingerprint):
    plugin = inspect(config, home(config)/identity)
    saved = approvals(config).get(identity, {})
    if not isinstance(saved, dict) or not plugin['compatible'] or plugin['fingerprint'] != fingerprint or saved.get('enabled') is not True or saved.get('fingerprint') != fingerprint:
        return None
    plugin['_approvalRevision'] = saved.get('revision')
    return plugin


def _monitor_environment(data_directory):
    # Avoid forwarding arbitrary app environment variables (which may contain
    # workspace or chat context). Plugins remain trusted code, not a sandbox.
    environment = {key: value for key, value in os.environ.items()
                   if key.upper() in {'SYSTEMROOT', 'WINDIR', 'SYSTEMDRIVE', 'TEMP', 'TMP', 'LANG', 'LC_ALL'}}
    if os.name == 'nt':
        system = Path(os.environ.get('SystemRoot', r'C:\Windows'))
        environment['PATH'] = os.pathsep.join((str(system/'System32'), str(system/'System32/WindowsPowerShell/v1.0')))
    else:
        environment['PATH'] = '/usr/bin:/bin'
    environment['AIBRAINWORX_PLUGIN_DATA'] = str(data_directory)
    return environment


def panels(config, context=None):
    """Collect opt-in API-1 panels with hot approval and source checks.

    A faulty plugin affects only its own row. Disabling, removing or changing
    source during collection discards that sample. Approvals and plugin data
    live under StateRoot, independently of app-source folder replacement.
    """
    items = []
    try:
        discovered = inventory(config)
    except (OSError, ValueError, TypeError, AttributeError):
        return {'items': [], 'detail': 'Local plugin inventory is unavailable.'}
    encoded = json.dumps({'apiVersion': API_VERSION, 'hook': 'monitor.sample', 'context': monitor_context(context)}, allow_nan=False)
    for public in discovered:
        if 'monitor.sample' not in public.get('hooks', []):
            continue
        # Manifest names are untrusted too; use the safe folder ID on failure.
        identity = public['id']
        try:
            name = _text(public.get('name', identity), 80)
        except ValueError:
            name = identity
        row = {key: public[key] for key in ('id', 'state', 'fingerprint')}
        row['name'] = name
        items.append(row)
        if public['state'] != 'enabled':
            row['detail'] = 'Review and approve this local code to enable its monitor.' if public['state'] == 'review' else 'This monitor needs a compatible plugin API.'
            continue
        try:
            plugin = _approved_monitor(config, identity, public['fingerprint'])
            if plugin is None:
                row.update(state='review', detail='Monitor approval or source changed. Refresh and review it again.')
                continue
            runtime = config.get('PythonExecutable') if plugin['runtime'] == 'python' else config.get('NodeExecutable')
            if not runtime or not Path(runtime).is_file():
                raise ValueError('Runtime unavailable.')
            data_directory = Path(config['StateRoot'])/'plugin-data'/identity
            data_directory.mkdir(parents=True, exist_ok=True)
            result = subprocess.run([runtime, plugin['_entry']], input=encoded, text=True, encoding='utf-8',
                                    capture_output=True, timeout=5, check=True, cwd=plugin['_directory'],
                                    env=_monitor_environment(data_directory), creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            # The approval and current source are checked AFTER collection as
            # well: stale in-flight results never revive a disabled panel.
            after = _approved_monitor(config, identity, public['fingerprint'])
            if after is None or after['_approvalRevision'] != plugin['_approvalRevision']:
                row.update(state='review', detail='Monitor approval or source changed. Sample discarded.')
                continue
            if len(result.stdout.encode('utf-8')) > 65536:
                raise ValueError('Monitor output too large.')
            reply = json.loads(result.stdout)
            if not isinstance(reply, dict) or type(reply.get('apiVersion')) is not int or reply['apiVersion'] != API_VERSION or set(reply)-{'apiVersion', 'panel'}:
                raise ValueError('Invalid monitor response.')
            row['panel'] = validate_panel(reply.get('panel'))
        except FileNotFoundError:
            row.update(state='removed', detail='Monitor files were removed. Refresh to update the list.')
        except Exception:
            # Never expose exception text, stdout, stderr or command arguments.
            row.update(state='error', detail='Monitor sample unavailable. Check its approved source and runtime.')
    return {'items': items}
