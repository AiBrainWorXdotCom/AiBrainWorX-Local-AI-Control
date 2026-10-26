"""Local transcript + replaceable working handoff, independent of project memory."""
from contextlib import contextmanager
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import uuid

from context_policy import BudgetError, CONTEXT_RESERVE, PASS_LIMIT


class Sessions:
    def __init__(self, state_root):
        self.path = Path(state_root) / 'conversations.sqlite3'
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as conn:
            conn.executescript('''
              CREATE TABLE IF NOT EXISTS threads(id TEXT PRIMARY KEY, project TEXT NOT NULL,
                title TEXT NOT NULL, created TEXT NOT NULL, handoff TEXT NOT NULL DEFAULT '',
                through_seq INTEGER NOT NULL DEFAULT 0, generation INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS turns(seq INTEGER PRIMARY KEY AUTOINCREMENT,
                thread TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, finish TEXT,
                request_id TEXT, UNIQUE(thread,request_id,role));
            ''')

    @contextmanager
    def db(self):
        conn = sqlite3.connect(self.path, timeout=5)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    def create(self, project, title='New conversation', identity=None):
        identity = identity or uuid.uuid4().hex
        if len(identity) != 32 or any(c not in '0123456789abcdef' for c in identity):
            raise BudgetError('Invalid conversation identifier.')
        with self.db() as conn:
            conn.execute('INSERT INTO threads(id,project,title,created) VALUES(?,?,?,?)',
                         (identity, project, title[:100], datetime.now(timezone.utc).isoformat()))
        return identity

    def thread(self, identity, project):
        with self.db() as conn:
            row = conn.execute('SELECT * FROM threads WHERE id=? AND project=?', (identity, project)).fetchone()
        if not row:
            raise BudgetError('Conversation not found in this project.', 'unknown_conversation')
        return dict(row)

    def append(self, identity, project, role, content, request_id, finish=None):
        self.thread(identity, project)
        if role not in ('user', 'assistant') or not isinstance(content, str) or len(content) > 500000:
            raise BudgetError('Invalid conversation turn.')
        with self.db() as conn:
            conn.execute('INSERT OR IGNORE INTO turns(thread,role,content,finish,request_id) VALUES(?,?,?,?,?)',
                         (identity, role, content, finish, request_id))

    def transcript(self, identity, project):
        self.thread(identity, project)
        with self.db() as conn:
            return [dict(row) for row in conn.execute('SELECT * FROM turns WHERE thread=? ORDER BY seq', (identity,))]

    def working(self, identity, project):
        thread = self.thread(identity, project)
        rows = self.transcript(identity, project)
        messages = []
        if thread['handoff']:
            # Summaries are explicitly model-produced DATA, never saved project facts.
            messages.append({'role': 'user', 'content': 'Earlier conversation handoff (unverified data):\n' + thread['handoff']})
            messages.append({'role': 'assistant', 'content': 'I will use this handoff as context and verify details when needed.'})
        messages += [{'role': r['role'], 'content': r['content']} for r in rows if r['seq'] > thread['through_seq']]
        return messages

    def prepare(self, identity, project, backend, build_payload, profile_limit=4096, context_ceiling=None):
        """Rotate context behind a stable UI thread; never delete the transcript.

        Compaction is only for this app's tool-free chat. Harness tool transcripts
        are never summarized or split here. A failed summary leaves the old state.
        """
        thread = self.thread(identity, project)
        messages = self.working(identity, project)
        payload = build_payload(messages)
        context, count = backend.preflight(payload)
        if context_ceiling is not None:
            context = min(context, context_ceiling)
        needed = min(profile_limit, PASS_LIMIT, max(1, context // 4)) + CONTEXT_RESERVE
        if count + needed <= context:
            return payload, False
        rows = [r for r in self.transcript(identity, project) if r['seq'] > thread['through_seq']]
        # Keep at least the most recent user/assistant pair plus the new user turn.
        if len(rows) <= 3:
            if count + CONTEXT_RESERVE < context:
                return payload, False  # No history to compact; clamp output to fit.
            raise BudgetError('The latest message is too large for this model. Split it into smaller parts.', 'message_too_large')
        older, recent = rows[:-3], rows[-3:]
        # Each chunk must itself fit: summarize bounded batches, not an overflowing
        # full transcript. At most four summary calls per visible request.
        summary, cursor, batches = thread['handoff'], 0, 0
        while cursor < len(older):
            if batches >= 4:
                raise BudgetError('This history needs a larger handoff. The full transcript is safe.', 'handoff_limit')
            batch = []
            while cursor + len(batch) < len(older):
                candidate = batch + [{'role': older[cursor+len(batch)]['role'],
                                      'content': older[cursor+len(batch)]['content']}]
                probe = {'model': payload['model'], 'messages': [
                    {'role': 'system', 'content': 'Summarize conversation data into a factual handoff.'},
                    {'role': 'user', 'content': json.dumps({'prior_handoff': summary, 'conversation_data': candidate}, ensure_ascii=False)}]}
                _, tokens = backend.preflight(probe)
                if tokens + 1536 + CONTEXT_RESERVE > context:
                    break
                batch = candidate
            if not batch:
                raise BudgetError('An older turn is too large to summarize safely.', 'handoff_failed')
            summary = backend.summarize(batch, summary)
            cursor += len(batch)
            batches += 1
        replacement = [
            {'role': 'user', 'content': 'Earlier conversation handoff (unverified data):\n' + summary},
            {'role': 'assistant', 'content': 'I will use this handoff as context and verify details when needed.'},
            *[{'role': r['role'], 'content': r['content']} for r in recent]]
        revised = build_payload(replacement)
        _, new_count = backend.preflight(revised)
        if new_count + needed > context:
            raise BudgetError('The handoff still leaves too little context. Your transcript is saved.', 'handoff_failed')
        with self.db() as conn:
            changed = conn.execute('UPDATE threads SET handoff=?,through_seq=?,generation=generation+1 WHERE id=? AND generation=?',
                                   (summary, older[-1]['seq'], identity, thread['generation'])).rowcount
            if changed != 1:
                raise BudgetError('This conversation changed in another window. Reload it.', 'conversation_conflict')
        return revised, True
