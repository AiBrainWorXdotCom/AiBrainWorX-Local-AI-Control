from copy import deepcopy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
from context_policy import BudgetError, can_continue, fit_request
from guarded_stream import events, repetition, stream
from conversation_sessions import Sessions
import project_memory


def request(**extra):
    return {'model': 'test', 'messages': [{'role': 'user', 'content': 'Write code'}], **extra}


def chunk(text='', reason=None, **delta):
    return {'choices': [{'index': 0, 'delta': {'content': text, **delta}, 'finish_reason': reason}]}


class ScriptBackend:
    def __init__(self, scripts, counts=None):
        self.scripts, self.counts, self.requests = scripts, iter(counts or [(32768, 100)] * 6), []
        self.closed = 0

    def preflight(self, payload):
        return next(self.counts)

    def stream(self, payload):
        self.requests.append(deepcopy(payload))
        try:
            yield from self.scripts[len(self.requests)-1]
        finally:
            self.closed += 1


def output(backend, payload=None, **kwargs):
    data = b''.join(stream(backend, payload or request(), **kwargs))
    parsed = list(events(io.BytesIO(data)))
    content = ''.join(c['delta'].get('content', '') for e in parsed for c in e.get('choices', []))
    return data, parsed, content


class Budgets(unittest.TestCase):
    def test_clamp_uses_full_prompt_and_256_reserve(self):
        fitted, budget = fit_request(request(max_tokens=4096), prompt_tokens=3700, server_context=4096)
        self.assertEqual(fitted['max_tokens'], 140)
        self.assertEqual(budget.output_tokens, 140)

    def test_exact_boundary_accepts_one_token(self):
        self.assertEqual(fit_request(request(), prompt_tokens=3839, server_context=4096)[1].output_tokens, 1)

    def test_exhausted_prompt_fails_before_backend_generation(self):
        for prompt in (3840, 4096, 10000):
            with self.assertRaises(BudgetError):
                fit_request(request(), prompt_tokens=prompt, server_context=4096)

    def test_alias_conflicts_choose_lower_and_normalize(self):
        value, _ = fit_request(request(max_tokens=99, max_completion_tokens=31), prompt_tokens=2, server_context=4096)
        self.assertNotIn('max_tokens', value)
        self.assertEqual(value['max_completion_tokens'], 31)

    def test_profile_and_total_remaining_are_hard_caps(self):
        value, _ = fit_request(request(max_tokens=10000), prompt_tokens=10, server_context=32768,
                               profile_limit=8000, total_remaining=700)
        self.assertEqual(value['max_tokens'], 700)

    def test_server_and_profile_context_use_lower(self):
        value, _ = fit_request(request(), prompt_tokens=3700, server_context=32768, context_ceiling=4096)
        self.assertEqual(value['max_tokens'], 140)

    def test_zero_and_minus_one_are_bounded_not_infinite(self):
        for limit in (0, -1):
            self.assertEqual(fit_request(request(max_tokens=limit), prompt_tokens=10, server_context=32768)[0]['max_tokens'], 4096)

    def test_invalid_number_types_rejected(self):
        for limit in (True, 2.5, '4096', -2):
            with self.assertRaises(BudgetError):
                fit_request(request(max_tokens=limit), prompt_tokens=1, server_context=4096)

    def test_continuation_requires_2048_plus_reserve(self):
        with self.assertRaises(BudgetError):
            fit_request(request(), prompt_tokens=1800, server_context=4096, continuation=True)

    def test_inputs_never_mutated(self):
        original = request(max_tokens=9999)
        before = deepcopy(original)
        fit_request(original, prompt_tokens=10, server_context=4096)
        self.assertEqual(original, before)


class Streams(unittest.TestCase):
    def test_two_extra_continuations_means_three_passes(self):
        backend = ScriptBackend([[chunk('A'*20, 'length')], [chunk('B'*20, 'length')], [chunk('C'*20, 'length')]])
        data, parsed, text = output(backend)
        self.assertEqual(len(backend.requests), 3)
        self.assertEqual(text, 'A'*20+'B'*20+'C'*20)
        self.assertEqual(data.count(b'data: [DONE]'), 1)
        final = parsed[-1]
        self.assertEqual(final['choices'][0]['finish_reason'], 'length')
        self.assertEqual(final['aibrainworx']['allocated_output_tokens'], 12288)
        self.assertEqual(final['aibrainworx']['guard'], 'continuation_limit')
        self.assertEqual(len({e['id'] for e in parsed}), 1)

    def test_stop_is_not_continued(self):
        backend = ScriptBackend([[chunk('Done', 'stop')]])
        self.assertEqual(output(backend)[2], 'Done')
        self.assertEqual(len(backend.requests), 1)

    def test_disabled_mode_reports_length_without_extra_request(self):
        backend = ScriptBackend([[chunk('partial', 'length')]])
        _, parsed, _ = output(backend, auto_continue=False)
        self.assertEqual(parsed[-1]['choices'][0]['finish_reason'], 'length')
        self.assertEqual(len(backend.requests), 1)

    def test_budget_recomputed_before_each_pass(self):
        backend = ScriptBackend([[chunk('first', 'length')]], [(4096, 100), (4096, 1900)])
        _, parsed, _ = output(backend)
        self.assertEqual(len(backend.requests), 1)
        self.assertEqual(parsed[-1]['aibrainworx']['guard'], 'continuation_headroom')

    def test_duplicate_preview_never_leaks(self):
        text = 'This is a repeated implementation explanation with sufficient distinctive words. ' * 5
        backend = ScriptBackend([[chunk(text, 'length')], [chunk(text, 'length')]])
        _, parsed, visible = output(backend)
        self.assertEqual(visible, text)
        self.assertEqual(parsed[-1]['aibrainworx']['guard'], 'repetition')

    def test_finish_chunk_content_is_not_lost(self):
        backend = ScriptBackend([[chunk('end of first', 'length')], [chunk('final suffix', 'stop')]])
        self.assertEqual(output(backend)[2], 'end of firstfinal suffix')

    def test_tool_and_structured_requests_not_stitched(self):
        for extra in ({'tools': [{'type': 'function'}]}, {'response_format': {'type': 'json_object'}},
                      {'reasoning_effort': 'high'}, {'previous_response_id': 'private-id'}):
            backend = ScriptBackend([[chunk('partial', 'length')]])
            output(backend, request(**extra))
            self.assertEqual(len(backend.requests), 1)

    def test_surprise_tool_call_turns_off_continuation(self):
        tool = [{'index': 0, 'function': {'name': 'inspect', 'arguments': '{'}}]
        backend = ScriptBackend([[chunk('', 'length', tool_calls=tool)]])
        _, parsed, _ = output(backend)
        self.assertEqual(parsed[0]['choices'][0]['delta']['tool_calls'], tool)
        self.assertEqual(len(backend.requests), 1)

    def test_truncated_stream_is_error_not_success(self):
        with self.assertRaises(BudgetError):
            output(ScriptBackend([[chunk('partial')]]))

    def test_cancel_closes_source_and_never_continues(self):
        state = {'cancelled': False}
        backend = ScriptBackend([[chunk('hello'), chunk('rest', 'length')]])
        generator = stream(backend, request(), cancelled=lambda: state['cancelled'])
        next(generator)
        state['cancelled'] = True
        self.assertEqual(list(generator), [])
        self.assertEqual(backend.closed, 1)

    def test_event_parser_multiline_and_utf8(self):
        wire = b': comment\r\ndata: {"choices": [],\r\ndata: "text": "\xe2\x9c\x93"}\r\n\r\ndata: [DONE]\r\n\r\n'
        self.assertEqual(list(events(io.BytesIO(wire)))[0]['text'], '\u2713')

    def test_repeated_short_code_delimiters_are_not_loop(self):
        self.assertFalse(repetition('}}\n', '}}\n'))

    def test_mutable_messages_do_not_change_original(self):
        original = request()
        before = deepcopy(original)
        output(ScriptBackend([[chunk('one', 'length')], [chunk('two', 'stop')]]), original)
        self.assertEqual(original, before)

    def test_first_pass_streams_before_source_finishes(self):
        backend = ScriptBackend([[chunk('first'), chunk('last', 'stop')]])
        generator = stream(backend, request())
        self.assertIn(b'first', next(generator))
        self.assertEqual(backend.closed, 0)
        generator.close()
        self.assertEqual(backend.closed, 1)


class SessionHandoff(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Sessions(self.temp.name)
        self.thread = self.store.create('project-A')

    def tearDown(self):
        self.temp.cleanup()

    def test_project_isolation(self):
        with self.assertRaises(BudgetError):
            self.store.thread(self.thread, 'project-B')

    def test_idempotent_append(self):
        for _ in range(2):
            self.store.append(self.thread, 'project-A', 'user', 'Hello', 'req1')
        self.assertEqual(len(self.store.transcript(self.thread, 'project-A')), 1)

    def populate(self):
        for index in range(9):
            self.store.append(self.thread, 'project-A', 'user' if index % 2 == 0 else 'assistant',
                              f'Turn {index}: ' + 'x'*400, str(index))

    def test_rollover_keeps_thread_and_full_transcript(self):
        self.populate()
        before = self.store.transcript(self.thread, 'project-A')
        class Counter:
            def preflight(self, payload):
                return 4096, sum(len(m['content']) for m in payload['messages'])
            def summarize(self, messages, previous=''):
                return 'The user is building a Linux launcher; testing is unfinished.'
        payload, rotated = self.store.prepare(self.thread, 'project-A', Counter(),
            lambda messages: request(messages=messages), profile_limit=2048)
        self.assertTrue(rotated)
        self.assertEqual(self.store.transcript(self.thread, 'project-A'), before)
        self.assertEqual(self.store.thread(self.thread, 'project-A')['generation'], 1)
        self.assertIn('unverified data', payload['messages'][0]['content'])

    def test_failed_summary_preserves_previous_context(self):
        self.populate()
        class Counter:
            def preflight(self, payload):
                return 4096, sum(len(m['content']) for m in payload['messages'])
            def summarize(self, messages, previous=''):
                raise BudgetError('Summary failed')
        with self.assertRaises(BudgetError):
            self.store.prepare(self.thread, 'project-A', Counter(), lambda m: request(messages=m), profile_limit=2048)
        self.assertEqual(self.store.thread(self.thread, 'project-A')['generation'], 0)
        self.assertEqual(len(self.store.transcript(self.thread, 'project-A')), 9)

    def test_handoff_never_creates_or_overwrites_project_memory(self):
        profile = {'workspaceRoot': self.temp.name, 'useMemory': False}
        config = {'StateRoot': self.temp.name}
        project_memory.save(config, profile, {'title': 'Owner decision', 'body': 'Keep the Windows app unchanged.',
                                            'kind': 'decision', 'verified': True})
        before = project_memory.items(config, profile)
        self.populate()
        self.assertEqual(project_memory.items(config, profile), before)
        self.assertEqual(project_memory.recall(config, profile)['text'], '')

    def test_first_turn_in_small_context_uses_output_clamp(self):
        self.store.append(self.thread, 'project-A', 'user', 'Hello', 'first')
        class Counter:
            def preflight(self, payload):
                return 4096, 3000
        payload, rotated = self.store.prepare(self.thread, 'project-A', Counter(), lambda m: request(messages=m))
        self.assertFalse(rotated)
        self.assertEqual(payload['messages'][-1]['content'], 'Hello')


if __name__ == '__main__':
    unittest.main()
