#!/usr/bin/env python3
"""
Classify the outcome of a streamed-JSON agent transcript.

Reads a captured stream-json transcript (one JSON object per line, possibly
interleaved with non-JSON noise) and prints a single JSON line describing
whether the run was rejected for capacity reasons, completed its intended
action, or failed some other way. The caller uses this to decide whether
retrying with a different credential could help.

Classifications:
    capacity_exhausted  the credential was rejected for usage/limit reasons;
                        a different credential may still succeed
    submitted           the marker tool call was seen, so the action happened
    other_failure       anything else; retrying with another credential will
                        not help

Usage:
    python classify-outcome.py <path-to-output-file> [--action-marker TOOL]
"""

import argparse
import json
import re
import sys
from typing import Any, Optional

# Any rejection carrying one of these shapes is a capacity rejection,
# whatever the period it applies to. Keyed on the structured event first,
# with the prose match kept only as a fallback for older output.
CAPACITY_TEXT_RE = re.compile(
    r"spending cap|hit your (?:weekly|session|daily|monthly|usage) limit|usage limit reached",
    re.IGNORECASE,
)
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


def _rate_limit_rejection(obj: dict[str, Any]) -> Optional[dict[str, Any]]:
    """The structured rejection event, if this object is one.

    The emitted event carries the period in ``rateLimitType`` (seven_day,
    five_hour, ...). The period is deliberately NOT part of the test: every
    period means the same thing to a caller holding more than one credential.
    """
    if obj.get("type") != "rate_limit_event":
        return None
    info = obj.get("rate_limit_info")
    if not isinstance(info, dict):
        return None
    if info.get("status") != "rejected":
        return None
    return info


def _is_rate_limit_error(obj: dict[str, Any]) -> bool:
    """True for a message tagged as a rate-limit error at the top level."""
    return obj.get("error") == "rate_limit"


def _is_capacity_result(obj: dict[str, Any]) -> bool:
    """True for an error result whose text reads as a usage/limit rejection."""
    if obj.get("type") != "result" or obj.get("is_error") is not True:
        return False
    result_text = obj.get("result")
    if not isinstance(result_text, str):
        return False
    return bool(CAPACITY_TEXT_RE.search(result_text))


def _result_text(objects: list[dict[str, Any]]) -> Optional[str]:
    for obj in objects:
        text = obj.get("result")
        if isinstance(text, str) and text:
            return text
    for obj in objects:
        message = obj.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text = item.get("text")
                if isinstance(text, str) and text:
                    return text
    return None


def _extract_resets_raw(text: Optional[str]) -> Optional[str]:
    if not text:
        return None
    match = RESETS_RE.search(text)
    return match.group(1) if match else None


def _has_action_marker_tool_use(obj: dict[str, Any], marker: str) -> bool:
    message = obj.get("message")
    if not isinstance(message, dict):
        return False
    content = message.get("content")
    if not isinstance(content, list):
        return False
    for item in content:
        if not isinstance(item, dict):
            continue
        if item.get("type") == "tool_use" and item.get("name") == marker:
            return True
    return False


def classify(lines: list[str], action_marker: Optional[str] = None) -> dict[str, Any]:
    """Classify a captured stream-json transcript.

    Args:
        lines: Raw text lines from the captured output file. Lines that do
            not parse as a JSON object are ignored.
        action_marker: Name of the tool call that proves the intended action
            was performed. When omitted, "submitted" is never reported.

    Returns:
        A dict with "classification", "resets_raw" (a clock string parsed from
        the message, or None) and "resets_at_epoch" (a unix timestamp taken
        from the structured event, or None). The epoch is authoritative where
        both are present: it is exact, and it can express a reset that is days
        away rather than a bare hour.
    """
    objects = _parse_json_lines(lines)

    for obj in objects:
        info = _rate_limit_rejection(obj)
        if info is None:
            continue
        resets_at = info.get("resetsAt")
        return {
            "classification": "capacity_exhausted",
            "resets_raw": _extract_resets_raw(_result_text(objects)),
            "resets_at_epoch": resets_at if isinstance(resets_at, int) else None,
            "limit_type": info.get("rateLimitType"),
        }

    for obj in objects:
        if _is_rate_limit_error(obj) or _is_capacity_result(obj):
            return {
                "classification": "capacity_exhausted",
                "resets_raw": _extract_resets_raw(_result_text(objects)),
                "resets_at_epoch": None,
                "limit_type": None,
            }

    if action_marker:
        for obj in objects:
            if _has_action_marker_tool_use(obj, action_marker):
                return {
                    "classification": "submitted",
                    "resets_raw": None,
                    "resets_at_epoch": None,
                    "limit_type": None,
                }

    return {
        "classification": "other_failure",
        "resets_raw": None,
        "resets_at_epoch": None,
        "limit_type": None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Classify a captured transcript.")
    parser.add_argument("output_path", help="Path to the captured output file")
    parser.add_argument(
        "--action-marker",
        default=None,
        help="Tool name whose presence proves the intended action was performed",
    )
    args = parser.parse_args()

    try:
        with open(args.output_path, encoding="utf-8") as handle:
            lines = handle.readlines()
    except OSError as exc:
        print(
            f"Error: could not read output file '{args.output_path}': {exc}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(json.dumps(classify(lines, args.action_marker)))


if __name__ == "__main__":
    main()
