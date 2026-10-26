"""Stable visible chat IDs with private working context, never project-memory writes."""
from copy import deepcopy
import json
import re
import threading
import weakref

from context_policy import BudgetError
from conversation_sessions import Sessions
import project_memory

_locks = weakref.WeakValueDictionary()
_mutex = threading.Lock()


class SessionRun:
    def __init__(self, config, profile, descriptor, message):
        if not isinstance(descriptor, dict) or not all(
                isinstance(descriptor.get(k), str) and re.fullmatch('[0-9a-f]{32}', descriptor[k])
                for k in ('id', 'requestId')):
            raise BudgetError('Invalid conversation request.')
        self.identity, self.request_id = descriptor['id'], descriptor['requestId']
        self.project = project_memory.project_key(profile)
        self.context_ceiling = profile['model']['contextWindow']
        self.store = Sessions(config['StateRoot'])
        self.text, self.reason, self.rotated = '', 'interrupted', False
        self.started = self.locked = False
        with _mutex:
            key = (config['StateRoot'], self.identity)
            lock = _locks.get(key)
            if lock is None:
                lock = threading.Lock()
                _locks[key] = lock
            # Retain a strong reference before the weak registry can release it.
            self.lock = lock
        if not self.lock.acquire(blocking=False):
            raise BudgetError('This conversation is already generating.', 'conversation_busy')
        self.locked = True
        try:
            try:
                self.store.thread(self.identity, self.project)
            except BudgetError as exc:
                if exc.code != 'unknown_conversation':
                    raise
                # create() cannot replace a thread belonging to another project.
                self.store.create(self.project, message[:100], self.identity)
            if any(r['request_id'] == self.request_id and r['role'] == 'assistant'
                   for r in self.store.transcript(self.identity, self.project)):
                raise BudgetError('This reply is already saved. Reload the conversation.', 'duplicate_request')
            self.store.append(self.identity, self.project, 'user', message, self.request_id)
            self.started = True
        except Exception:
            self.close()
            raise

    def prepare(self, backend, build, cap):
        payload, self.rotated = self.store.prepare(self.identity, self.project, backend, build, cap, self.context_ceiling)
        return payload

    def record(self, frame):
        # guarded_stream emits one JSON event per frame; errors and DONE have no text.
        if not frame.startswith(b'data: {'):
            return
        row = json.loads(frame[6:].decode())
        for choice in row.get('choices', []):
            text = choice.get('delta', {}).get('content', '')
            if isinstance(text, str):
                self.text += text
            if choice.get('finish_reason'):
                self.reason = choice['finish_reason']

    def close(self):
        try:
            if self.started and self.text:
                self.store.append(self.identity, self.project, 'assistant', self.text,
                                  self.request_id, self.reason)
                self.started = False
        finally:
            if self.locked:
                self.lock.release()
                self.locked = False


def prepare(config, profile, selected, request, route, backend, enrich):
    descriptor = request.pop('aibrainworx_session', None)
    if descriptor is None:
        return enrich(request), None
    if route != '/v1/chat/completions' or request.get('tools') or request.get('functions'):
        raise BudgetError('Automatic handoffs are restricted to tool-free built-in chat.')
    messages = request.get('messages')
    if not isinstance(messages, list) or len(messages) != 1 or messages[0].get('role') != 'user' or not isinstance(messages[0].get('content'), str):
        raise BudgetError('A session request needs exactly one new user message.')
    session = SessionRun(config, profile, descriptor, messages[0]['content'])
    def build(history):
        body = deepcopy(request)
        body['messages'] = history
        return enrich(body)
    try:
        payload = session.prepare(backend, build, profile['maxOutputTokens'])
        return payload, session
    except Exception:
        session.close()
        raise
