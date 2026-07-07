#!/usr/bin/env python3
"""
Classify the outcome of a streamed-JSON agent transcript.

Reads a captured stream-json transcript (one JSON object per line, possibly
interleaved with non-JSON noise) and prints a single JSON line describing
whether the run hit a usage/spending limit, completed its action, or failed
some other way. Used to decide whether to retry with an alternate credential.

Usage:
    python classify-outcome.py <path-to-output-file>
"""

import json
import re
import sys
from typing import Any, Optional

# Presence of this tool call in the stream means the intended action was posted.
ACTION_MARKER_TOOL_NAME = "mcp__github__pull_request_review_write"

SPENDING_CAP_RE = re.compile(r"spending cap", re.IGNORECASE)
RESETS_RE = re.compile(
    r"resets?\s+(\d{1,2}(?::\d{2})?\s*[ap]m|\d{1,2}(?::\d{2})?)",
    re.IGNORECASE,
)


def _parse_json_lines(lines: list[str]) -> list[dict[str, Any]]:
    """Parse each line as JSON, silently skipping lines that are not valid JSON."""
    parsed: list[dict[str, Any]] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            parsed.append(obj)
    return parsed


def _is_spending_cap_result(obj: dict[str, Any]) -> bool:
    if obj.get("type") != "result":
        return False
    if obj.get("is_error") is not True:
        return False
    result_text = obj.get("result")
    if not isinstance(result_text, str):
        return False
    return bool(SPENDING_CAP_RE.search(result_text))


def _extract_resets_raw(result_text: str) -> Optional[str]:
    match = RESETS_RE.search(result_text)
    if not match:
        return None
    return match.group(1)


def _has_action_marker_tool_use(obj: dict[str, Any]) -> bool:
    message = obj.get("message")
    if not isinstance(message, dict):
        return False
    content = message.get("content")
    if not isinstance(content, list):
        return False
    for item in content:
        if not isinstance(item, dict):
            continue
        if (
            item.get("type") == "tool_use"
            and item.get("name") == ACTION_MARKER_TOOL_NAME
        ):
            return True
    return False


def classify(lines: list[str]) -> dict[str, Optional[str]]:
    """Classify a captured stream-json transcript.

    Args:
        lines: Raw text lines from the captured output file. Lines that do
            not parse as a JSON object are ignored.

    Returns:
        A dict with "classification" (one of "spending_cap", "submitted",
        "other_failure") and "resets_raw" (the extracted clock string, or
        None).
    """
    objects = _parse_json_lines(lines)

    for obj in objects:
        if _is_spending_cap_result(obj):
            result_text = obj["result"]
            return {
                "classification": "spending_cap",
                "resets_raw": _extract_resets_raw(result_text),
            }

    for obj in objects:
        if _has_action_marker_tool_use(obj):
            return {"classification": "submitted", "resets_raw": None}

    return {"classification": "other_failure", "resets_raw": None}


def main() -> None:
    if len(sys.argv) != 2:
        print(
            "Usage: python classify-outcome.py <path-to-output-file>",
            file=sys.stderr,
        )
        sys.exit(1)

    output_path = sys.argv[1]
    try:
        with open(output_path, encoding="utf-8") as handle:
            lines = handle.readlines()
    except OSError as exc:
        print(
            f"Error: could not read output file '{output_path}': {exc}",
            file=sys.stderr,
        )
        sys.exit(1)

    result = classify(lines)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
