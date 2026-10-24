"""Original AiBrainWorX project memory: explicit notes, bounded recall and history.

Uses Python's SQLite only. No hosted memory service, embeddings or transcript
capture. This implementation contains no OpenHuman or TinyMemory source.
"""
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import uuid

KINDS = ('fact', 'decision', 'task', 'handoff')
CONTEXT_CHARS = 4000


def project_key(profile):
    return hashlib.sha256(str(Path(profile['workspaceRoot']).resolve()).casefold().encode()).hexdigest()


@contextmanager
def database(config):
    path = Path(config['StateRoot']) / 'memory' / 'aibrainworx-memory.sqlite3'
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.executescript('''
        CREATE TABLE IF NOT EXISTS notes(
            id TEXT PRIMARY KEY, project TEXT NOT NULL, title TEXT NOT NULL,
            body TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL,
            pinned INTEGER NOT NULL, verified INTEGER NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0, updated TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS notes_project ON notes(project, archived);
        CREATE TABLE IF NOT EXISTS revisions(
            sequence INTEGER PRIMARY KEY AUTOINCREMENT, note_id TEXT NOT NULL,
            project TEXT NOT NULL, previous TEXT NOT NULL, changed TEXT NOT NULL);
    ''')
    try:
        with conn:
            yield conn
    finally:
        conn.close()


def items(config, profile, query='', archived=False):
    with database(config) as conn:
        rows = [dict(r) for r in conn.execute('SELECT * FROM notes WHERE project=? AND archived=? ORDER BY pinned DESC,updated DESC LIMIT 500', (project_key(profile), int(archived)))]
    terms = set(re.findall(r'[^\W_]{2,}', str(query).casefold())[:12])
    if terms:
        rows = [r for r in rows if any(t in (r['title']+' '+r['body']+' '+r['source']).casefold() for t in terms)]
    return rows


def save(config, profile, payload):
    title = payload.get('title', '').strip()
    body = payload.get('body', '').strip()
    source = payload.get('source', '').strip()
    kind = payload.get('kind', 'fact')
    if not title or len(title) > 120 or not body or len(body) > 4000 or len(source) > 500 or '\x00' in title+body+source or kind not in KINDS:
        raise ValueError('Memory needs a title (120 characters), note (4000 maximum) and valid type. Source is optional (500 maximum).')
    for field in ('pinned', 'verified'):
        if type(payload.get(field, False)) is not bool:
            raise ValueError('Invalid memory checkbox value.')
    identity = payload.get('id') or uuid.uuid4().hex
    key = project_key(profile)
    stamp = datetime.now(timezone.utc).isoformat()
    with database(config) as conn:
        old = conn.execute('SELECT * FROM notes WHERE id=?', (identity,)).fetchone()
        if old and old['project'] != key:
            raise ValueError('That memory belongs to another project.')
        if old:
            if payload.get('updated') != old['updated']:
                raise ValueError('This memory was edited elsewhere. Reload it before saving.')
            conn.execute('INSERT INTO revisions(note_id,project,previous,changed) VALUES(?,?,?,?)', (identity,key,json.dumps(dict(old)),stamp))
        conn.execute('INSERT INTO notes VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,kind=excluded.kind,source=excluded.source,pinned=excluded.pinned,verified=excluded.verified,updated=excluded.updated',
                     (identity,key,title,body,kind,source,int(payload.get('pinned',False)),int(payload.get('verified',False)),0,stamp))
    return dict(id=identity, updated=stamp, note='Saved locally for this project. Other model profiles for the same folder share this memory.')


def archive(config, profile, payload):
    with database(config) as conn:
        old = conn.execute('SELECT * FROM notes WHERE id=? AND project=?', (payload.get('id'),project_key(profile))).fetchone()
        if not old:
            raise ValueError('Memory was not found in this project.')
        conn.execute('INSERT INTO revisions(note_id,project,previous,changed) VALUES(?,?,?,?)', (old['id'],old['project'],json.dumps(dict(old)),datetime.now(timezone.utc).isoformat()))
        conn.execute('UPDATE notes SET archived=? WHERE id=? AND project=?', (0 if payload.get('restore') else 1,old['id'],old['project']))
    return dict(note='Restored.' if payload.get('restore') else 'Archived. It can be restored from the Archive view.')


def latest_question(body, route):
    candidates = body.get('input', []) if route == '/v1/responses' else body.get('messages', [])
    if isinstance(candidates, str):
        return candidates[-2000:]
    if not isinstance(candidates, list):
        return ''
    for message in reversed(candidates):
        if isinstance(message, dict) and message.get('role') == 'user':
            content = message.get('content', '')
            if isinstance(content, str):
                return content[-2000:]
            if isinstance(content, list):
                return ' '.join(str(p.get('text','')) for p in content if isinstance(p,dict))[-2000:]
    return ''


def recall(config, profile, query=''):
    if not profile.get('useMemory'):
        return dict(text='', records=[], characters=0, note='Project memory is disabled for this profile.')
    rows = items(config, profile)
    terms = set(re.findall(r'[^\W_]{2,}', query.casefold())[:12])
    def score(row):
        text = (row['title']+' '+row['body']).casefold()
        return (bool(row['pinned']), sum(t in text for t in terms), row['updated'])
    rows.sort(key=score, reverse=True)
    text = ''; selected = []
    for row in rows:
        if len(selected) == 6:
            break
        block = f"\n[{row['kind']}; {'user-marked verified' if row['verified'] else 'unverified note'}] {row['title']}\n{row['body']}"
        if row['source']:
            block += '\nSource: '+row['source']
        remaining = CONTEXT_CHARS - len(text)
        if remaining < 120:
            break
        text += block[:remaining]
        selected.append(dict(id=row['id'],title=row['title'],kind=row['kind']))
    if text:
        text = 'AiBrainWorX project memory (reference context; may be stale; follow current user instructions):\n'+text
    return dict(text=text, records=selected, characters=len(text), note='Local saved notes only. This preview shows the context available for the next request; relevance depends on its user message.')


def handoff(config, profile):
    rows = items(config, profile)
    model = profile['model']
    lines = ['# AiBrainWorX project handoff','',f"Created: {datetime.now(timezone.utc).isoformat()}",
             f"Profile: {profile['name']}",f"Model: {model['backend']} / {model['modelId']}",'',
             'This export contains saved project notes, not the full chat transcript. Review before sharing.','']
    for kind in KINDS:
        selected = [r for r in rows if r['kind']==kind]
        if selected:
            lines += ['## '+kind.title()+'s','']
            for row in selected:
                lines += ['### '+row['title'],row['body'],('Source: '+row['source']) if row['source'] else '', '']
    lines += ['## Next session','', '- Review the saved decisions and open tasks.','- Confirm the selected model, project and current file state.','- Run relevant checks; distinguish user notes from verified results.','']
    return dict(markdown='\n'.join(lines), records=len(rows))
