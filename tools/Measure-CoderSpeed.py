"""Repeat the short Coder request pattern against an already-loaded local Strata.

Standard library only. Does not start/download a model or change saved settings.
Run with --plan to inspect requests without contacting any service.
"""
import argparse
from datetime import datetime, timezone
import hashlib
from http.client import HTTPConnection
import json
from pathlib import Path
import time


def request(method, route, body=None):
    connection = HTTPConnection('127.0.0.1', 8081, timeout=180 if body else 5)
    try:
        connection.request(method, route, None if body is None else json.dumps(body).encode(),
                           {} if body is None else {'Content-Type': 'application/json'})
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError(f'Local {route} returned HTTP {response.status}; benchmark stopped.')
        return json.loads(response.read())
    finally:
        connection.close()


def cases(stamp):
    repeated = f'Speed check {stamp} repeated. Write a compact Python clamp(value, low, high) function that raises ValueError if low > high. Include three asserts. Output only code.'
    return [
        ('varied-merge', f'Speed check {stamp} A. Write a concise Python merge_sorted(a, b) function using two pointers. Both lists are already sorted. Return a new list. Include one assert. Output only code.', 256),
        ('varied-typescript', f'Speed check {stamp} B. Write concise TypeScript code for groupBy<T>(items, keyFn) returning Map<string,T[]>. Include one tiny usage example. Output only code.', 256),
        ('varied-sql', f'Speed check {stamp} C. Given orders(id, customer_id, amount, created_at), write a SQL query returning the top five customers by total amount for calendar year 2025. Include customer_id and total_amount. Then explain the date filter in one sentence.', 256),
    ] + [(f'repeat-{i}', repeated, 160) for i in range(1, 4)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true', help='Print the six requests; no network or file writes.')
    parser.add_argument('--output', type=Path, help='New output JSON file. Existing files are not overwritten.')
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    prompts = cases(stamp)
    if args.plan:
        print(json.dumps({'endpoint': 'http://127.0.0.1:8081', 'requests': prompts,
                          'temperature': 0, 'reasoning_effort': 'none'}, indent=2))
        return
    output = args.output or Path(f'coder-speed-{stamp}.json')
    if output.exists():
        parser.error('Output already exists. Choose a new file.')
    health = request('GET', '/health')
    if health.get('service') != 'strata' or not health.get('loaded') or health.get('model') != 'qwen3.8-flash-next-coder-iq1_m':
        raise RuntimeError('Expected Strata Coder IQ1_M must already be loaded. Nothing was started.')
    observations = {'started_utc': stamp, 'model': health['model'],
                    'conditions': 'Already-loaded engine; temp0; reasoning none; sequential direct loopback. Short samples only.',
                    'trials': []}
    # Reserve an unused file before requests; retain completed observations on errors.
    with output.open('x', encoding='utf-8') as file:
        json.dump(observations, file, indent=2)
    try:
        for name, prompt, cap in prompts:
            before = request('GET', '/metrics')
            if before.get('live', {}).get('state') != 'idle' or before.get('live', {}).get('queued', 0):
                raise RuntimeError('Another request is active or queued; stopped without interrupting it.')
            old_ids = {r.get('id') for r in before.get('requests', [])}
            started = time.perf_counter()
            reply = request('POST', '/v1/chat/completions', {
                'model': 'qwen3.8-flash-next-coder', 'messages': [{'role': 'user', 'content': prompt}],
                'temperature': 0, 'reasoning_effort': 'none', 'max_tokens': cap, 'stream': False})
            elapsed = time.perf_counter() - started
            new_records = [r for r in request('GET', '/metrics').get('requests', []) if r.get('id') not in old_ids]
            if len(new_records) != 1:
                raise RuntimeError('Concurrent request changed telemetry; sample not attributed.')
            metrics = new_records[0]
            choice = reply['choices'][0]
            usage = reply.get('usage', {})
            if usage.get('completion_tokens') != metrics.get('output_tokens') or usage.get('prompt_tokens') != metrics.get('prompt_tokens'):
                raise RuntimeError('Telemetry usage differs from this reply; sample not attributed.')
            sample = dict(name=name, max_output_tokens=cap, elapsed_seconds=round(elapsed, 4),
                          decode_tokens_per_second=metrics.get('decode_tok_s'),
                          first_engine_token_seconds=metrics.get('first_engine_token_s'),
                          cached_input_tokens=metrics.get('reused'), usage=usage,
                          finish_reason=choice.get('finish_reason'),
                          response_sha256=hashlib.sha256((choice.get('message', {}).get('content') or '').encode()).hexdigest())
            observations['trials'].append(sample)
            output.write_text(json.dumps(observations, indent=2)+'\n', encoding='utf-8')
            print(json.dumps(sample), flush=True)
    finally:
        output.write_text(json.dumps(observations, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
