"""Parse Granite Guardian's structured classification for Guardrails input and output rails."""

import json
import re

from nemoguardrails.actions import action
from nemoguardrails.actions.rail_outcome import RailOutcome
from nemoguardrails.library.self_check.input_check.actions import self_check_input
from nemoguardrails.llm.output_parsers import is_content_safe


def quoted_text_task(user_input):
    """Recognize requests to process quoted text without obeying its commands."""
    if not re.match(r"\s*(summarize|translate|explain|analyze|describe)\b", user_input, re.IGNORECASE):
        return False
    quote_pattern = r"(?<!\w)(['\"])(.*?)\1(?!\w)"
    if not re.search(quote_pattern, user_input, re.DOTALL):
        return False
    outside = re.sub(quote_pattern, " ", user_input, flags=re.DOTALL)
    return not re.search(
        r"\b(ignore|forget|override|reveal|disclose|print|show|send|disable|"
        r"bypass|follow|obey|pretend|and|then|before)\b|"
        r"\b(act as|turn off|after that|from now on|do it)\b",
        outside,
        re.IGNORECASE,
    )


@action(is_system_action=True)
async def guardian_input_check(
    llms,
    llm_task_manager,
    context=None,
    events=None,
    llm=None,
    config=None,
    variant=None,
    user_message=None,
    **kwargs,
):
    user_input = user_message if user_message is not None else (context or {}).get("user_message")
    if user_input and quoted_text_task(user_input):
        return RailOutcome.allow()
    return await self_check_input(
        llms=llms,
        llm_task_manager=llm_task_manager,
        context=context,
        events=events,
        llm=llm,
        config=config,
        variant=variant,
        user_message=user_message,
        **kwargs,
    )


def guardian_score(response):
    """Return NeMo's safety flag from Guardian's structured answer."""
    try:
        answer = json.loads(response)
    except json.JSONDecodeError:
        answer = None
    if isinstance(answer, dict) and isinstance(answer.get("attack"), bool):
        return [not answer["attack"]]
    score = re.search(r"<score>\s*(yes|no)\s*</score>", response, re.IGNORECASE)
    if score:
        return [score.group(1).lower() == "no"]
    return is_content_safe(response)


def guardian_output_score(response):
    """Accept only an explicit safe decision for an assistant response."""
    try:
        answer = json.loads(response)
    except (TypeError, json.JSONDecodeError):
        return [False]
    if isinstance(answer, dict) and isinstance(answer.get("unsafe"), bool):
        return [not answer["unsafe"]]
    return [False]


def init(app):
    app.register_output_parser(guardian_score, "guardian_score")
    app.register_output_parser(guardian_output_score, "guardian_output_score")
    app.register_action(guardian_input_check, "self_check_input")
