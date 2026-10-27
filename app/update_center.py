"""Read-only component update inventory. Downloads metadata, never software/weights."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import base64
import hashlib
import json
from pathlib import Path
import re

import app_updates
import control_core as core
import plugin_host

STRATA_FEED = 'https://github.com/Niko1221/Strata/releases/latest/download/strata-feed.json'
STRATA_URL = 'https://github.com/Niko1221/Strata/releases'
HARNESS_URL = 'https://github.com/deepseek-ai/deepseek-harness/releases'
REPO_ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}/[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$')
REVISION = re.compile(r'^[0-9a-f]{40}$')


def read_local(path, default=None):
    try:
        path = Path(path)
        if path.stat().st_size > 2*1024*1024:
            return default
        return json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError, TypeError):
        return default


def row(name, kind, installed='', latest='', state='unknown', detail='', url='', **extra):
    return dict(name=name, kind=kind, installed=installed or 'Not recorded', latest=latest or 'Not checked',
                state=state, detail=detail, url=url, **extra)


def compare(installed, latest):
    if not installed:
        return 'review'
    try:
        own, remote = app_updates.version_key(installed), app_updates.version_key(latest)
        return 'available' if remote > own else 'current' if remote == own else 'ahead'
    except ValueError:
        # A tag we cannot order is not evidence of either safety or freshness.
        return 'current' if installed == latest else 'review'


def installed_harness(config):
    entry = Path(config.get('HarnessEntry', ''))
    # The CLI lives at package/lib/bin.js in the installed official npm package.
    for parent in list(entry.parents)[:4]:
        data = read_local(parent / 'package.json', {})
        if data.get('name') == '@deepseek-ai/dsh':
            return data.get('version', '')
    return ''


def launcher(current, previews, config=None):
    result = app_updates.check(current, previews, (config or {}).get('LauncherRepository'))
    return row('AiBrainWorX Launcher', 'Application', current, result.get('latest'), result['state'],
               result['detail'], result['url'])


def strata(config):
    if not config.get('StrataRoot'):
        return [row('Strata', 'Optional runtime', state='unknown',
                    detail='No local Strata installation is configured. Connect an installation to check its components.', url=STRATA_URL)]
    root = Path(config.get('StrataRoot', ''))
    current = ''
    try:
        source = (root / 'strata_cli/__init__.py').read_text(encoding='utf-8')
        match = re.search(r'PRODUCT_VERSION\s*=\s*[\'"]([^\'"]+)', source)
        current = match[1] if match else ''
    except OSError:
        pass
    engine = read_local(root / 'engine/engine-component.json', {})
    results = []
    try:
        feed = app_updates.request_json(STRATA_FEED)
        latest = feed.get('app', {}).get('version', '')
        if not latest:
            raise ValueError('Missing version')
        results.append(row('Strata application / CLI', 'Runtime', current, latest, compare(current, latest),
            'Official release-feed metadata. Review compatibility before installing.', STRATA_URL))
        # DeepSeek's dsv41 engine is a different component. Never compare its
        # version to the installed Qwen engine or compare engine vs app versions.
        packages = (feed.get('engine') or {}).get('packages', [])
        build = str(engine.get('build_id', ''))
        variant = ('cuda13' if 'cuda13' in build else 'cuda12' if 'cuda12' in build else engine.get('variant'))
        matches = [p for p in packages if p.get('platform') == engine.get('platform')
                   and p.get('backend') == engine.get('backend') and variant and p.get('variant') == variant]
        if matches:
            package = max(matches, key=lambda p: app_updates.version_key(p['version']))
            results.append(row('Strata Qwen engine', 'Engine', engine.get('version'), package['version'],
                compare(engine.get('version'), package['version']),
                'Matching platform/backend component. Driver and runtime requirements still apply; nothing was installed.', STRATA_URL))
        else:
            results.append(row('Strata engine', 'Engine', engine.get('version'), state='review',
                detail='No exact platform/backend variant match was recorded. Review the release notes.', url=STRATA_URL))
    except (OSError, ValueError, KeyError, TypeError):
        results = [row('Strata application / CLI', 'Runtime', current, state='unavailable',
                       detail='The official update feed could not be verified. This is not an up-to-date result.', url=STRATA_URL),
                   row('Strata engine', 'Engine', engine.get('version'), state='unavailable',
                       detail='Installed component retained; retry the metadata check.', url=STRATA_URL)]
    return results


def harness(config, previews):
    current = installed_harness(config)
    try:
        data = app_updates.request_json('https://registry.npmjs.org/@deepseek-ai/dsh/latest')
        latest = data['version']
        # npm's latest tag can legitimately point at a prerelease. Honor the UI filter.
        if not previews and '-' in latest:
            return row('DeepSeek Harness', 'Coding client', current, latest, 'review',
                       'The current npm latest tag is a prerelease; preview updates are disabled.', HARNESS_URL)
        return row('DeepSeek Harness', 'Coding client', current, latest, compare(current, latest),
                   'Official @deepseek-ai/dsh npm metadata; package update requires your review.', HARNESS_URL)
    except (OSError, ValueError, KeyError, TypeError):
        return row('DeepSeek Harness', 'Coding client', current, state='unavailable',
                   detail='Could not check the official npm package.', url=HARNESS_URL)


def model_sources(config, state):
    tracked = read_local(Path(config['StateRoot']) / 'model-sources.local.json', {})
    entries = {}
    for profile in state['profiles'][:100]:
        model = profile.get('model', {})
        key = model.get('backend', '') + ':' + model.get('modelId', '')
        if key in entries:
            continue
        saved = tracked.get(key, {}) if isinstance(tracked, dict) else {}
        repo = saved.get('repo') or model.get('sourceRepo') or ''
        revision = saved.get('revision') or model.get('sourceRevision') or ''
        # A full Hub model ID is identifiable; a runtime alias is not provenance.
        if not repo and REPO_ID.fullmatch(model.get('modelId', '')):
            repo = model['modelId']
        entries[key] = dict(key=key, name=model.get('modelId', 'Model'), repo=repo, revision=revision)
    strata_root = config.get('StrataRoot')
    if strata_root:
        for path in sorted(Path(strata_root).glob('strata-*.json'))[:32]:
            data = read_local(path, {})
            name = data.get('model_name')
            if not isinstance(name, str) or not name:
                continue
            # An alias already represented by a profile is the same installation.
            if any('strata:'+alias in entries for alias in [name, *data.get('aliases', [])] if isinstance(alias, str)):
                continue
            key = 'strata:' + name
            saved = tracked.get(key, {}) if isinstance(tracked, dict) else {}
            entries[key] = dict(key=key, name=name, repo=saved.get('repo', ''), revision=saved.get('revision', ''))
    return list(entries.values())[:32]


def model(entry):
    repo, revision = entry['repo'], entry['revision']
    if not REPO_ID.fullmatch(repo):
        return row(entry['name'], 'Model', state='review',
            detail='Connect its original Hugging Face model card to check revisions. Runtime aliases do not identify exact weights.',
            trackingKey=entry['key'], sourceRepo='')
    url = 'https://huggingface.co/' + repo
    try:
        data = app_updates.request_json('https://huggingface.co/api/models/' + repo)
        latest = data['sha']
        if not REVISION.fullmatch(latest):
            raise ValueError('Missing model revision')
        state = 'review' if not REVISION.fullmatch(revision) else 'current' if revision == latest else 'available'
        detail = ('The upstream revision matches your recorded installation.' if state == 'current' else
                  'The upstream repository changed. Review file/quant changes before downloading; weights were not checked or replaced.' if state == 'available' else
                  'Latest upstream revision found; the installed commit was not recorded. Freshness is unknown.')
        return row(entry['name'], 'Model', revision[:12], latest[:12], state, detail, url,
                   trackingKey=entry['key'], sourceRepo=repo, fullRevision=latest)
    except (OSError, ValueError, KeyError, TypeError):
        return row(entry['name'], 'Model', revision[:12], state='unavailable',
                   detail='Could not check this public model card. Gated/private metadata may require visiting its source.',
                   url=url, trackingKey=entry['key'], sourceRepo=repo)


def skills(root):
    catalog = read_local(root / 'skills/catalog.json', [])
    results = []
    bundled = [r for r in catalog if r.get('path')]
    try:
        tree = app_updates.request_json(app_updates.API+'/git/trees/main?recursive=1')
        if tree.get('truncated'):
            raise ValueError('Incomplete tree')
        upstream = {item['path']: item['sha'] for item in tree.get('tree', []) if item.get('type') == 'blob'}
        for entry in bundled:
            relative = 'skills/' + entry['path']
            path = (root / relative).resolve()
            if not path.is_relative_to((root/'skills').resolve()):
                raise ValueError('Invalid skill path')
            data = path.read_bytes().replace(b'\r\n', b'\n')
            own = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            latest = upstream.get(relative)
            state = 'current' if own == latest else 'review'
            results.append(row(entry['name'], 'Bundled skill', own[:8], (latest or '')[:8], state,
                'Bundled guide matches public main.' if state == 'current' else
                'The bundled guide differs from public main. Review local edits before replacing.',
                app_updates.REPOSITORY + '/blob/main/' + relative))
    except (OSError, ValueError, KeyError, TypeError):
        results.append(row('Bundled skills ('+str(len(bundled))+')', 'Skills', state='unavailable',
                           detail='Could not compare the public source tree. Local skill files were preserved.', url=app_updates.REPOSITORY+'/tree/main/skills'))
    for entry in catalog:
        url = entry.get('url', '')
        if entry.get('path') or not url.startswith('https://github.com/'):
            continue
        repo = url.removeprefix('https://github.com/').rstrip('/')
        if not REPO_ID.fullmatch(repo):
            continue
        try:
            commits = app_updates.request_json('https://api.github.com/repos/'+repo+'/commits?per_page=1')
            latest = commits[0]['sha']
            changed = latest != entry.get('revision')
            results.append(row(entry['name'], 'Skill reference', entry.get('revision', '')[:8], latest[:8],
                'review' if changed else 'current',
                'Upstream changed since the reviewed reference. Not installed; review license and scripts first.' if changed else
                'Upstream matches the recorded reference. This reference is not an installed skill.', url))
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            results.append(row(entry['name'], 'Skill reference', entry.get('revision', '')[:8], state='unavailable',
                               detail='Could not check the upstream reference. Nothing was installed.', url=url))
    return results


def save_model_source(config, payload):
    state = core.ensure_state(config)
    valid = {item['key'] for item in model_sources(config, state)}
    key, repo, revision = payload.get('key'), payload.get('repo', '').strip(), payload.get('revision', '').strip()
    if key not in valid or not REPO_ID.fullmatch(repo) or (revision and not REVISION.fullmatch(revision)):
        raise ValueError('Choose an installed profile model, an owner/repository model card and an optional full 40-character installed commit.')
    path = Path(config['StateRoot']) / 'model-sources.local.json'
    with core.state_lock(config):
        data = read_local(path, {})
        data[key] = {'repo': repo, 'revision': revision}
        core.write_json(path, data)
    return {'note': 'Model source saved locally. A blank installed revision remains unverified.'}


def user_plugins(config):
    rows = []
    for entry in plugin_host.inventory(config):
        url = entry.get('updateRepository', '')
        if entry.get('state') in ('invalid', 'incompatible'):
            rows.append(row(entry.get('name', entry['id']), 'User plugin', entry.get('version'), state='review',
                            detail='Plugin disabled because its manifest or API is incompatible. User files are preserved.'))
            continue
        if not isinstance(url, str) or not url.startswith('https://github.com/') or not REPO_ID.fullmatch(url.removeprefix('https://github.com/')):
            rows.append(row(entry.get('name', entry['id']), 'User plugin', entry.get('version'), state='review',
                            detail='Local user customization; no upstream release source recorded. The launcher never overwrites it.'))
            continue
        try:
            release = app_updates.request_json('https://api.github.com/repos/'+url.removeprefix('https://github.com/')+'/releases/latest')
            latest = release['tag_name']
            rows.append(row(entry.get('name', entry['id']), 'User plugin', entry.get('version'), latest,
                            compare(entry.get('version'), latest), 'Read-only release check. New plugin code requires review and approval.', url+'/releases'))
        except (OSError, ValueError, TypeError, KeyError):
            rows.append(row(entry.get('name', entry['id']), 'User plugin', entry.get('version'), state='unavailable',
                            detail='Could not check the plugin release source. Local files remain untouched.', url=url))
    return rows


def progress_path(config, identity):
    """HELP-UPDATES: private progress records identify this check, never a download."""
    if not isinstance(identity, str) or not re.fullmatch(r'[a-f0-9]{32}', identity):
        raise ValueError('Choose a valid update-check identifier.')
    directory = Path(config['StateRoot'])/'update-checks'
    if directory.exists() and (directory.is_symlink() or (hasattr(directory, 'is_junction') and directory.is_junction())):
        raise ValueError('Update progress directory must not be a link.')
    return directory/(identity+'.local.json')


def progress_writer(config, identity):
    path = progress_path(config, identity)
    def save(value):
        core.write_json(path, value)
    return save


def check(config, current, previews=True, root=None, progress=None):
    root = Path(root or core.ROOT)
    state = core.ensure_state(config)
    jobs = [lambda: launcher(current, previews, config), lambda: strata(config),
            lambda: harness(config, previews), lambda: skills(root), lambda: user_plugins(config)]
    jobs += [lambda entry=entry: model(entry) for entry in model_sources(config, state)]
    rows, results = [], {}
    def notify(completed):
        if progress:
            try:
                progress(dict(completed=completed, total=len(jobs),
                              state='complete' if completed == len(jobs) else 'checking', unit='checks'))
            except OSError:
                pass  # A progress-file failure cannot change a source check result.
    notify(0)
    with ThreadPoolExecutor(max_workers=4) as executor:
        def run(job):
            try:
                return job()
            except Exception:
                return row('Component check', 'Diagnostics', state='unavailable',
                           detail='A component check could not complete. Local installations were preserved.')
        futures = {executor.submit(run, job): index for index, job in enumerate(jobs)}
        for future in as_completed(futures):
            results[futures[future]] = future.result()
            notify(len(results))
    # Preserve the inventory's stable order while reporting real completion order.
    for index in range(len(jobs)):
        result = results[index]
        rows.extend(result if isinstance(result, list) else [result])
    summary = {name: sum(r['state'] == name for r in rows) for name in
               ('available', 'current', 'ahead', 'review', 'unavailable', 'unknown', 'no-release')}
    return dict(checkedAt=datetime.now(timezone.utc).isoformat(), components=rows, summary=summary,
                detail='Read-only check complete. Model revisions are not weight checksums. No packages, models or skills were installed or restarted.')
