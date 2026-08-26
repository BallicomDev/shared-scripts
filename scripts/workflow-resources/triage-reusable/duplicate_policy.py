#!/usr/bin/env python3
"""Shared duplicate-handling policy for the triage auto-close step and the
hourly duplicate sweep.

Pure logic only — no network access — so it is unit-testable in
tests/unit/triage_reusable/test_duplicate_policy.py and importable by both
close_duplicates.py (event-time HIGH close) and the duplicate-sweep scripts.

Policy (LOCKED DESIGN, PROPOSAL.md):
- Only same-repo, ``confidence: HIGH`` + ``type: duplicate`` findings are
  actionable at event time; ``related`` never closes anything.
- Survivor rule splits on provenance: an error-monitor pair keeps the
  OLDEST issue (canonical occurrence history); a human-filed pair keeps the
  NEWEST (current triage/sizing) unless the older issue carries work
  evidence (size-approved label, ``time:`` entries, commit references), in
  which case the decision inverts and the newer issue closes.
- An issue with work evidence is never closed; if both sides carry
  evidence, no action is taken at all.
"""

import json
import os
import re
from typing import Any, Dict, List, Optional, Tuple

TRIAGE_BOT_LOGIN = "github-actions[bot]"
TRIAGE_MARKER = "## Triage Analysis"
SUPERSEDED_MARKER = "TRIAGE_SUPERSEDED"
ERROR_MONITOR_LABEL = os.environ.get("ERROR_MONITOR_LABEL", "error-monitor")
SIZE_APPROVED_LABEL = os.environ.get("SIZE_APPROVED_LABEL", "size-approved")

_METADATA_RE = re.compile(r"==METADATA==(.*?)==METADATA==", re.DOTALL)
_TIME_ENTRY_RE = re.compile(r"^\s*time:\s*\d+(?:\.\d+)?h\b", re.IGNORECASE | re.MULTILINE)
_ISSUE_NUMBER_RE = re.compile(r"^#?(\d+)$")


def extract_metadata(comment_body: str) -> Optional[Dict[str, Any]]:
    """Parse the ==METADATA== JSON block out of a triage comment body.

    Tolerates the block appearing with or without the usual HTML-comment
    wrapper, and JSON wrapped across multiple lines. Returns None when no
    parseable block exists.
    """
    match = _METADATA_RE.search(comment_body or "")
    if not match:
        return None
    try:
        parsed = json.loads(match.group(1))
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    return parsed


def select_live_triage_comment(comments: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Return the NEWEST non-superseded triage-bot comment, or None.

    The first triage comment on an issue can itself be superseded, so the
    caller must never take comments[0] (or blindly the last comment): the
    live analysis is the newest bot comment carrying the triage marker
    without the superseded marker.
    """
    live = None
    for comment in comments:
        body = comment.get("body") or ""
        login = (comment.get("user") or {}).get("login", "")
        if login != TRIAGE_BOT_LOGIN:
            continue
        if TRIAGE_MARKER not in body or SUPERSEDED_MARKER in body:
            continue
        live = comment
    return live


def _parse_issue_number(value: Any) -> Optional[int]:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        match = _ISSUE_NUMBER_RE.match(value.strip())
        if match:
            return int(match.group(1))
    # Anything else (cross-repo "owner/repo#N", null, objects) is not a
    # same-repo target and must be skipped, never guessed at.
    return None


def normalise_duplicate_entries(metadata: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Normalise the metadata ``duplicates`` array against schema drift.

    Observed oddities (accuracy audit, PROPOSAL.md): entries missing
    ``type`` (treated as duplicate-candidates) or ``reason``; issue numbers
    as strings. Entries whose target cannot be resolved to a same-repo
    issue number are dropped.
    """
    raw = metadata.get("duplicates")
    if not isinstance(raw, list):
        return []
    entries = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        number = _parse_issue_number(item.get("issue"))
        if number is None:
            continue
        entries.append(
            {
                "issue": number,
                "confidence": str(item.get("confidence", "")).upper(),
                "type": str(item.get("type") or "duplicate").lower(),
                "reason": str(item.get("reason") or ""),
            }
        )
    return entries


def actionable_high_duplicates(metadata: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Entries eligible for auto-close: HIGH confidence, duplicate type."""
    return [
        entry
        for entry in normalise_duplicate_entries(metadata)
        if entry["confidence"] == "HIGH" and entry["type"] == "duplicate"
    ]


def work_evidence(issue: Dict[str, Any]) -> Tuple[bool, str]:
    """Detect management/work state that must never be auto-closed away.

    ``issue`` carries pre-fetched data: ``labels`` (list of names),
    ``comments`` (list of {body}), ``timeline`` (list of timeline events).
    """
    if SIZE_APPROVED_LABEL in issue.get("labels", []):
        return True, f"carries the {SIZE_APPROVED_LABEL} label"
    for comment in issue.get("comments", []):
        if _TIME_ENTRY_RE.search(comment.get("body") or ""):
            return True, "has time: entries logged"
    for event in issue.get("timeline", []):
        if event.get("event") == "referenced" and event.get("commit_id"):
            return True, "is referenced by commits"
    return False, ""


def decide_survivor(issue_a: Dict[str, Any], issue_b: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Apply the provenance-split survivor rule to a confirmed duplicate pair.

    Each issue dict needs: ``number``, ``created_at`` (ISO 8601, textually
    sortable), ``labels`` and ``has_work_evidence``. Returns a decision
    ``{"close": n, "survivor": n, "rule": str}`` or None when no safe action
    exists (both sides carry work evidence).
    """
    older, newer = sorted([issue_a, issue_b], key=lambda i: i["created_at"])
    both_error_monitor = all(ERROR_MONITOR_LABEL in issue.get("labels", []) for issue in (older, newer))
    if both_error_monitor:
        preferred_close, other = newer, older
        rule = "error-monitor pair: keep oldest canonical"
    else:
        preferred_close, other = older, newer
        rule = "human-filed pair: keep newest"

    if preferred_close.get("has_work_evidence"):
        if other.get("has_work_evidence"):
            return None
        preferred_close, other = other, preferred_close
        rule += " (inverted: preferred close target carries work evidence)"

    return {
        "close": preferred_close["number"],
        "survivor": other["number"],
        "rule": rule,
    }


def closing_comment(survivor: int, rule: str, reason: str) -> str:
    """The single short comment left on the issue being closed."""
    lines = [
        f"Closed as a duplicate of #{survivor} — that issue is the surviving ticket " "for this work.",
        "",
        f"_Survivor rule: {rule}._",
    ]
    if reason:
        lines.append(f"_Triage reason: {reason}_")
    lines += ["", "---", "*Closed automatically by triage duplicate auto-close*"]
    return "\n".join(lines)


def survivor_comment(closed: int) -> str:
    """The single short comment left on the surviving issue."""
    return (
        f"Supersedes #{closed}, closed as a duplicate of this issue; its history "
        "remains readable there.\n\n"
        "Do not reopen closed duplicates — new evidence goes here.\n\n"
        "---\n"
        "*Posted automatically by triage duplicate auto-close*"
    )
