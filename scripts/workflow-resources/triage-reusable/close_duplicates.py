#!/usr/bin/env python3
"""Event-time HIGH-confidence duplicate auto-close.

Runs as a post-analysis step in triage-reusable.yml, strictly AFTER the
triage analysis comment is confirmed posted (see ai-tools#574 on why
ordering matters): it re-fetches the issue's comments itself, selects the
NEWEST non-superseded triage comment, parses its ==METADATA== block and
acts only on same-repo ``confidence: HIGH`` + ``type: duplicate`` findings.

Survivor rule and comment texts live in duplicate_policy.py (shared with
the hourly duplicate sweep). Closing an issue means: one short cross-link
comment on each side, the ``duplicate`` label on the closed issue, then
close as not_planned. Runs on the caller repo's own GITHUB_TOKEN
(issues:write in its own repo) — never cross-repo.

Required environment variables: REPOSITORY (owner/repo), ISSUE_NUMBER,
GITHUB_TOKEN. Optional: DRY_RUN ("true" logs planned actions only).
"""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

SCRIPT_DIR = Path(__file__).resolve().parent

_spec = importlib.util.spec_from_file_location("duplicate_policy", SCRIPT_DIR / "duplicate_policy.py")
assert _spec and _spec.loader
policy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(policy)


def gh_api(args: List[str]) -> Any:
    """Run ``gh api`` and return parsed JSON. Fails fast on error."""
    result = subprocess.run(["gh", "api", *args], capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def fetch_issue_bundle(repo: str, number: int) -> Optional[Dict[str, Any]]:
    """Fetch issue + comments + timeline as the flat dict the policy expects.

    Returns None when the number is a pull request or does not exist.
    """
    try:
        issue = gh_api([f"repos/{repo}/issues/{number}"])
    except subprocess.CalledProcessError as exc:
        print(f"WARNING: could not fetch {repo}#{number}: {exc.stderr.strip()}")
        return None
    if issue is None or "pull_request" in issue:
        return None
    comments = gh_api([f"repos/{repo}/issues/{number}/comments", "--paginate"]) or []
    timeline = (
        gh_api(
            [
                f"repos/{repo}/issues/{number}/timeline",
                "--paginate",
                "-H",
                "Accept: application/vnd.github+json",
            ]
        )
        or []
    )
    return {
        "number": number,
        "state": issue.get("state", ""),
        "created_at": issue.get("created_at", ""),
        "labels": [label["name"] for label in issue.get("labels", [])],
        "comments": comments,
        "timeline": timeline,
    }


def plan_pair_action(own_issue: Dict[str, Any], target_issue: Dict[str, Any], reason: str) -> Optional[Dict[str, Any]]:
    """Turn a claimed duplicate pair into a concrete close plan, or None.

    Skips: self-references, targets no longer open, and pairs where no safe
    close exists (both sides carry work evidence).
    """
    if target_issue["number"] == own_issue["number"]:
        return None
    if target_issue.get("state") != "open" or own_issue.get("state") != "open":
        return None
    enriched = []
    for issue in (own_issue, target_issue):
        has_evidence, _ = policy.work_evidence(issue)
        enriched.append(dict(issue, has_work_evidence=has_evidence))
    decision = policy.decide_survivor(enriched[0], enriched[1])
    if decision is None:
        return None
    return {
        "close": decision["close"],
        "survivor": decision["survivor"],
        "rule": decision["rule"],
        "close_comment": policy.closing_comment(decision["survivor"], decision["rule"], reason),
        "survivor_comment": policy.survivor_comment(decision["close"]),
    }


def execute_plan(repo: str, plan: Dict[str, Any], dry_run: bool) -> None:
    close_n, survivor_n = plan["close"], plan["survivor"]
    print(f"Closing {repo}#{close_n} as duplicate of #{survivor_n} ({plan['rule']})")
    if dry_run:
        print("DRY_RUN: no writes performed")
        return
    subprocess.run(
        [
            "gh",
            "label",
            "create",
            "duplicate",
            "--repo",
            repo,
            "--color",
            "cfd3d7",
            "--description",
            "This issue or pull request already exists",
            "--force",
        ],
        check=True,
    )
    subprocess.run(
        [
            "gh",
            "issue",
            "edit",
            str(close_n),
            "--repo",
            repo,
            "--add-label",
            "duplicate",
        ],
        check=True,
    )
    subprocess.run(
        [
            "gh",
            "issue",
            "comment",
            str(survivor_n),
            "--repo",
            repo,
            "--body",
            plan["survivor_comment"],
        ],
        check=True,
    )
    subprocess.run(
        [
            "gh",
            "issue",
            "close",
            str(close_n),
            "--repo",
            repo,
            "--reason",
            "not planned",
            "--comment",
            plan["close_comment"],
        ],
        check=True,
    )
    print(f"Closed {repo}#{close_n}; survivor #{survivor_n} cross-linked")


def main() -> int:
    repo = os.environ["REPOSITORY"]
    issue_number = int(os.environ["ISSUE_NUMBER"])
    dry_run = os.environ.get("DRY_RUN", "false").lower() == "true"

    comments = gh_api([f"repos/{repo}/issues/{issue_number}/comments", "--paginate"]) or []
    live = policy.select_live_triage_comment(comments)
    if live is None:
        print("No live (non-superseded) triage comment found — nothing to do")
        return 0
    metadata = policy.extract_metadata(live.get("body", ""))
    if metadata is None:
        print("Live triage comment carries no parseable metadata — nothing to do")
        return 0
    entries = policy.actionable_high_duplicates(metadata)
    if not entries:
        print("No HIGH-confidence duplicate findings — nothing to do")
        return 0

    own_issue = fetch_issue_bundle(repo, issue_number)
    if own_issue is None:
        print(f"Could not fetch own issue {repo}#{issue_number} — aborting")
        return 1

    acted = 0
    for entry in entries:
        target = fetch_issue_bundle(repo, entry["issue"])
        if target is None:
            print(f"Skipping #{entry['issue']}: not a fetchable same-repo issue")
            continue
        plan = plan_pair_action(own_issue, target, entry["reason"])
        if plan is None:
            print(
                f"Skipping pair #{issue_number}/#{entry['issue']}: "
                "no safe close (closed, self-reference, or work evidence on both sides)"
            )
            continue
        execute_plan(repo, plan, dry_run)
        acted += 1
        if plan["close"] == issue_number:
            # Our own issue just closed; do not process further entries.
            break
    print(f"Duplicate auto-close complete: {acted} action(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
