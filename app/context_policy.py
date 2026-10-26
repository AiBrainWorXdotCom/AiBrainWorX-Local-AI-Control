"""Explicit output budgets. Counts must describe the final rendered prompt.

No character/4 estimate, prompt truncation, hidden context expansion or model reload.
"""
from copy import deepcopy
from dataclasses import asdict, dataclass

CONTEXT_RESERVE = 256
PASS_LIMIT = 4096
MAX_CONTINUATIONS = 2  # Two EXTRA requests, three passes total.
TOTAL_OUTPUT_LIMIT = 12288
MIN_CONTINUATION_ROOM = 2048


class BudgetError(ValueError):
    def __init__(self, message, code="context_budget", details=None):
        super().__init__(message)
        self.code, self.details = code, details or {}


@dataclass(frozen=True)
class Budget:
    context_tokens: int
    prompt_tokens: int
    reserve_tokens: int
    output_tokens: int
    requested_tokens: int

    def view(self):
        return asdict(self)


def positive(value, name):
    if type(value) is not int or value < 1:
        raise BudgetError(f"{name} must be a positive integer.")
    return value


def fit_request(payload, *, prompt_tokens, server_context, profile_limit=4096,
                total_remaining=TOTAL_OUTPUT_LIMIT, context_ceiling=None,
                continuation=False):
    """Return a copy, with both output aliases normalized to the lower cap."""
    result = deepcopy(payload)
    ctx = positive(server_context, "Running server context")
    if context_ceiling is not None:
        ctx = min(ctx, positive(context_ceiling, "Profile context"))
    if type(prompt_tokens) is not int or prompt_tokens < 0:
        raise BudgetError("A verified prompt token count is required.")
    profile_limit = positive(profile_limit, "Profile output cap")
    remaining = positive(total_remaining, "Remaining output budget")
    requests = []
    for key in ("max_tokens", "max_completion_tokens", "max_output_tokens"):
        if key in result:
            value = result[key]
            if type(value) is not int or value < -1:
                raise BudgetError("Output limits must be integer token counts.")
            if value > 0:
                requests.append(value)
    requested = min(requests) if requests else profile_limit
    room = ctx - prompt_tokens - CONTEXT_RESERVE
    if room < 1:
        raise BudgetError("The prompt needs a context handoff before generation.",
                          "context_full", {"context": ctx, "prompt": prompt_tokens,
                                           "reserve": CONTEXT_RESERVE})
    if continuation and room < MIN_CONTINUATION_ROOM:
        raise BudgetError("Not enough context for a safe continuation.", "continuation_headroom")
    cap = min(requested, profile_limit, PASS_LIMIT, remaining, room)
    # Sending conflicting aliases can make different backends choose different caps.
    key = ("max_output_tokens" if "max_output_tokens" in result else
           "max_completion_tokens" if "max_completion_tokens" in result else "max_tokens")
    for alias in ("max_tokens", "max_completion_tokens", "max_output_tokens"):
        result.pop(alias, None)
    result[key] = cap
    return result, Budget(ctx, prompt_tokens, CONTEXT_RESERVE, cap, requested)


def can_continue(payload):
    """Only ordinary, stateless, single-choice text chat can be concatenated."""
    if payload.get("n", 1) != 1 or payload.get("tools") or payload.get("functions"):
        return False
    formatting = payload.get('response_format') or {}
    if not isinstance(formatting, dict) or formatting.get("type", "text") != "text":
        return False
    if any(payload.get(k) for k in ("grammar", "json_schema", "previous_response_id", "conversation", "logprobs")):
        return False
    if payload.get("reasoning_effort") not in (None, "none"):
        return False
    messages = payload.get("messages")
    return (isinstance(messages, list) and bool(messages) and
            all(isinstance(m, dict) and m.get("role") in ("system", "user", "assistant")
                and isinstance(m.get("content"), str)
                and not any(m.get(k) for k in ("tool_calls", "function_call", "reasoning_content"))
                for m in messages))
