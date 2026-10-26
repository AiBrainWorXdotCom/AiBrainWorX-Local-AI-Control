"""Preview-first, three-way customization transfer into a separate update folder.

No downloads, service control, Git resets, package installation or code execution.
Requires an explicit apply call after reviewing the returned plan.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import uuid

USER_DIRS = ('customizations', 'plugins', 'prompts', 'profiles')
PRIVATE_NAMES = {'.env', 'auth.json', 'cookies.txt'}
TEXT_SUFFIXES = {'.py', '.ps1', '.js', '.mjs', '.cjs', '.ts', '.json', '.toml', '.yaml', '.yml', '.md', '.txt', '.css', '.html', '.sh'}
MAX_BYTES = 8 * 1024 * 1024
MAX_FILES = 2000


def digest(path):
    path = Path(path)
    if not path.is_file():
        return None
    if path.stat().st_size > MAX_BYTES:
        raise ValueError('A migration file exceeds the 8 MiB safety limit.')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_file(root, relative):
    raw = Path(relative)
    if raw.is_absolute() or '..' in raw.parts or not raw.parts:
        raise ValueError('Migration paths must stay inside their installation folder.')
    path = root / raw
    for candidate in (path, *path.parents):
        if candidate == root.parent:
            break
        if candidate.is_symlink() or (hasattr(candidate, 'is_junction') and candidate.is_junction()):
            raise ValueError('Symlinks and junctions are not transferred.')
    if not path.resolve().is_relative_to(root):
        raise ValueError('Migration path escapes the installation folder.')
    return path


def roots(source, target):
    source, target = Path(source).resolve(), Path(target).resolve()
    if not source.is_dir() or not target.is_dir() or source == target or source.is_relative_to(target) or target.is_relative_to(source):
        raise ValueError('Use two existing, separate installation folders.')
    return source, target


def plan(source, target, baseline=None):
    source, target = roots(source, target)
    baseline = baseline or {}
    if not isinstance(baseline, dict) or any(not isinstance(k, str) or not isinstance(v, str) or len(v) != 64 for k, v in baseline.items()):
        raise ValueError('The baseline must map shipped relative filenames to SHA-256 values.')
    candidates = set(baseline)
    for folder in USER_DIRS:
        directory = safe_file(source, folder)
        if directory.is_dir():
            for path in directory.rglob('*'):
                if len(candidates) >= MAX_FILES:
                    raise ValueError('Too many files for an automatic migration plan.')
                if path.is_file() or path.is_symlink():
                    candidates.add(path.relative_to(source).as_posix())
    if (source / 'config.local.json').is_file():
        candidates.add('config.local.json')
    actions, conflicts, skipped = [], [], []
    for relative in sorted(candidates):
        src, dst = safe_file(source, relative), safe_file(target, relative)
        if not src.exists():
            # A locally deleted shipped file can represent a customization too.
            if relative in baseline and dst.exists():
                conflicts.append({'path': relative, 'reason': 'Locally deleted shipped file; review whether the update reintroduces it.'})
            continue
        if src.name in PRIVATE_NAMES or src.name.startswith('.env.') or src.suffix.lower() not in TEXT_SUFFIXES:
            skipped.append({'path': relative, 'reason': 'Credential, binary, database or non-text asset; transfer separately.'})
            continue
        own, remote, base = digest(src), digest(dst), baseline.get(relative)
        if own == remote:
            continue
        user_owned = relative == 'config.local.json' or Path(relative).parts[0] in USER_DIRS
        if base and own == base:
            continue  # No customization; leave the candidate update's newer file.
        if base and remote != base:
            conflicts.append({'path': relative, 'reason': 'Both local and upstream changed, or upstream removed this file. Manual merge required.'})
            continue
        if not base and not user_owned:
            skipped.append({'path': relative, 'reason': 'No shipped baseline. Cannot infer ownership.'})
            continue
        if user_owned and remote is not None and not base:
            conflicts.append({'path': relative, 'reason': 'The candidate already has different user data. Nothing will be overwritten.'})
            continue
        # Decode before planning a code/config transfer; never transplant opaque binaries.
        src.read_text(encoding='utf-8-sig')
        actions.append({'path': relative, 'source_sha256': own, 'target_sha256': remote})
    return dict(schemaVersion=1, source=str(source), target=str(target), actions=actions,
                conflicts=conflicts, skipped=skipped, canApply=not conflicts,
                vendorBaselineRecorded=bool(baseline),
                note=('Preview only. Running services and external state are untouched. '
                      'Without the original shipped baseline, direct vendor edits cannot be certified; '
                      'this plan covers recognized customization folders and local config only.'))


def apply(report):
    if report.get('schemaVersion') != 1 or report.get('conflicts') or not report.get('canApply'):
        raise ValueError('Resolve migration conflicts before applying this plan.')
    source, target = roots(report['source'], report['target'])
    actions = report['actions']
    if len(actions) > MAX_FILES:
        raise ValueError('Too many migration actions.')
    # Verify the complete plan before any writes; do not overwrite files edited
    # since preview. Each write is verified again and has a target-side backup.
    for item in actions:
        src, dst = safe_file(source, item['path']), safe_file(target, item['path'])
        if digest(src) != item['source_sha256'] or digest(dst) != item['target_sha256']:
            raise ValueError('Files changed after preview. Generate a fresh plan.')
    identity = uuid.uuid4().hex
    backup = target / '.aibrainworx-migration-backups' / identity
    backup.mkdir(parents=True, mode=0o700)
    completed = []
    for item in actions:
        src, dst = safe_file(source, item['path']), safe_file(target, item['path'])
        data = src.read_bytes()
        if hashlib.sha256(data).hexdigest() != item['source_sha256'] or digest(dst) != item['target_sha256']:
            raise ValueError('A file changed during migration. Review the candidate folder and backup.')
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists():
            saved = backup / item['path']
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dst, saved)
        temporary = dst.with_name(dst.name+'.migration-'+identity)
        try:
            with temporary.open('xb') as handle:
                handle.write(data)
            os.chmod(temporary, 0o600 if item['path'] == 'config.local.json' else src.stat().st_mode & 0o777)
            if digest(dst) != item['target_sha256']:
                raise ValueError('A candidate file changed; refusing to replace it.')
            if item['target_sha256'] is None:
                # Exclusive final creation prevents a late conflicting new file.
                with dst.open('xb') as handle:
                    handle.write(data)
                shutil.copymode(temporary, dst)
            else:
                os.replace(temporary, dst)
            completed.append(item['path'])
        finally:
            temporary.unlink(missing_ok=True)
    result = {'copied': completed, 'backup': str(backup), 'sourceModified': False,
              'servicesRestarted': False, 'at': datetime.now(timezone.utc).isoformat()}
    (backup/'report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result
