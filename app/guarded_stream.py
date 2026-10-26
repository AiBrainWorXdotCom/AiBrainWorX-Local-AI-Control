"""Bounded Chat Completions continuation with valid OpenAI SSE framing."""
from copy import deepcopy
from difflib import SequenceMatcher
import json
import time
import uuid

from context_policy import (BudgetError, MAX_CONTINUATIONS, TOTAL_OUTPUT_LIMIT,
                            can_continue, fit_request)

PREVIEW_CHARS = 240
MAX_EVENT_BYTES = 1024 * 1024
MAX_STREAM_BYTES = 4 * 1024 * 1024
MAX_SECONDS = 600


def events(response):
    """Parse SSE records, including multiple data lines and split UTF-8 bytes."""
    data, size = [], 0
    for raw in response:
        size += len(raw)
        if size > MAX_EVENT_BYTES:
            raise BudgetError("The backend sent an oversized SSE event.", "invalid_stream")
        line = raw.decode("utf-8", errors="strict").rstrip("\r\n")
        if not line:
            if data:
                value = "\n".join(data)
                if value == "[DONE]":
                    return
                yield json.loads(value)
            data, size = [], 0
        elif line.startswith("data:"):
            data.append(line[5:].lstrip(" "))
    if data:
        value = "\n".join(data)
        if value != "[DONE]":
            yield json.loads(value)


def frame(event):
    return ("data: " + json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n\n").encode()


def repetition(previous, following):
    tail, head = previous[-PREVIEW_CHARS:].strip(), following[:PREVIEW_CHARS].strip()
    if min(len(tail), len(head)) < 48:
        return False  # Short braces and ordinary delimiters are legitimate code.
    if SequenceMatcher(None, tail, head, autojunk=False).ratio() > .85:
        return True
    words = following.split()
    grams = [tuple(words[i:i+5]) for i in range(max(0, len(words)-4))]
    return len(grams) >= 24 and len(set(grams)) / len(grams) < .20


def stream(backend, payload, profile_limit=4096, context_ceiling=None,
           auto_continue=True, cancelled=lambda: False):
    """backend.preflight returns (actual per-slot context, rendered prompt count).

    backend.stream returns an iterator of decoded OpenAI chunk objects. No automatic
    retry after an error. A budget reserves each pass's cap even if usage is absent;
    token counts never come from the number of SSE chunks or len(text)//4.
    """
    original = deepcopy(payload)
    current = deepcopy(payload)
    current["stream"] = True
    enabled = auto_continue and can_continue(current)
    identity = "chatcmpl-awx-" + uuid.uuid4().hex
    created, started = int(time.time()), time.monotonic()
    allocated, actual_output, byte_count = 0, 0, 0
    complete_usage = True
    previous = ""
    aggregate = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    last_reason, guard = "stop", None

    def packet(delta, finish=None, extra=None):
        row = {"id": identity, "object": "chat.completion.chunk", "created": created,
               "model": original.get("model", ""),
               "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
        if extra:
            row.update(extra)
        return row

    for pass_index in range(MAX_CONTINUATIONS + 1):
        if cancelled():
            return
        if time.monotonic() - started > MAX_SECONDS:
            last_reason, guard = "length", "time_limit"
            break
        try:
            context, count = backend.preflight(current)
            request, budget = fit_request(current, prompt_tokens=count, server_context=context,
                profile_limit=profile_limit, context_ceiling=context_ceiling,
                total_remaining=TOTAL_OUTPUT_LIMIT-allocated, continuation=pass_index > 0)
        except BudgetError as exc:
            if pass_index == 0:
                raise
            last_reason, guard = "length", exc.code
            break
        # Count the full allocation, including reasoning and any unreported tokens.
        allocated += budget.output_tokens
        turn, preview = "", []
        preview_ready = pass_index == 0
        finished, usage_seen, unsafe = False, False, False
        seen_reason = None
        source = backend.stream(request)
        try:
            for event in source:
                if cancelled():
                    return
                if time.monotonic() - started > MAX_SECONDS:
                    last_reason, guard, unsafe = "length", "time_limit", True
                    break
                if event.get("error"):
                    raise BudgetError("The model returned a streaming error.", "backend_error")
                choices = event.get("choices", [])
                if len(choices) > 1 or (choices and choices[0].get("index", 0) != 0):
                    raise BudgetError("Continuation requires one response choice.", "invalid_stream")
                usage = event.get("usage")
                if isinstance(usage, dict):
                    # One final usage event per pass. Never double-count duplicates.
                    if not usage_seen:
                        for name in aggregate:
                            value = usage.get(name, 0)
                            if type(value) is not int or value < 0:
                                raise BudgetError("Invalid backend token usage.", "invalid_usage")
                            aggregate[name] += value
                        actual_output += usage.get("completion_tokens", 0)
                        usage_seen = True
                        if actual_output > TOTAL_OUTPUT_LIMIT:
                            raise BudgetError("The backend exceeded the output allowance.", "backend_limit_violation")
                if not choices:
                    continue
                choice = choices[0]
                delta = deepcopy(choice.get("delta") or {})
                content = delta.get("content", "")
                if not isinstance(content, str):
                    raise BudgetError("Unsupported content delta.", "invalid_stream")
                byte_count += len(content.encode("utf-8"))
                if byte_count > MAX_STREAM_BYTES:
                    last_reason, guard, unsafe = "length", "byte_limit", True
                    break
                if any(delta.get(k) for k in ("tool_calls", "function_call", "reasoning_content", "refusal", "audio")):
                    enabled = False
                if pass_index:
                    delta.pop("role", None)
                turn += content
                reason = choice.get("finish_reason")
                if reason is not None:
                    finished, seen_reason = True, reason
                if not preview_ready:
                    preview.append(delta)
                    if len(turn) < PREVIEW_CHARS and not finished:
                        continue
                    if repetition(previous, turn):
                        last_reason, guard, unsafe = "length", "repetition", True
                        break
                    preview_ready = True
                    for item in preview:
                        if item:
                            yield frame(packet(item))
                    preview.clear()
                elif delta:
                    yield frame(packet(delta))
                if finished:
                    # Continue reading the usage event and upstream [DONE].
                    last_reason = seen_reason
            if not preview_ready and preview and not unsafe:
                if repetition(previous, turn):
                    last_reason, guard, unsafe = "length", "repetition", True
                else:
                    for item in preview:
                        if item:
                            yield frame(packet(item))
        finally:
            close = getattr(source, "close", None)
            if close:
                close()
        if unsafe:
            break
        complete_usage = complete_usage and usage_seen
        if not finished:
            raise BudgetError("The upstream stream ended without a finish reason.", "incomplete_stream")
        if last_reason != "length" or not enabled:
            break
        if not turn.strip():
            guard = "empty_output"
            break
        if pass_index == MAX_CONTINUATIONS:
            guard = "continuation_limit"
            break
        if allocated >= TOTAL_OUTPUT_LIMIT:
            guard = "total_output_limit"
            break
        previous = turn
        # Conversation continuation is explicit, supported Chat Completions. Raw
        # assistant prefill is backend-specific; do not assume it preserves syntax.
        current["messages"].extend([
            {"role": "assistant", "content": turn},
            {"role": "user", "content": "Continue directly from the cutoff. Do not repeat prior output or add an introduction."}])

    extra = {"aibrainworx": {"continuations": pass_index, "guard": guard,
                             "allocated_output_tokens": allocated}}
    yield frame(packet({}, last_reason, extra))
    if original.get("stream_options", {}).get("include_usage"):
        # Missing usage is never represented as a measured zero.
        yield frame({"id": identity, "object": "chat.completion.chunk", "created": created,
                     "model": original.get("model", ""), "choices": [],
                     "usage": aggregate if complete_usage and usage_seen else None})
    yield b"data: [DONE]\n\n"
