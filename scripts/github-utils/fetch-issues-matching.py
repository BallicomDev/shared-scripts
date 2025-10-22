#!/usr/bin/env python3
"""
Generic issue fetcher with filtering and complete data retrieval.
Finds issues matching criteria and fetches complete data for each.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def run_command(cmd, capture_output=True):
    """Execute command and return result."""
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=capture_output,
        text=True
    )
    return result


def fetch_matching_issues(repo, label=None, state="open", limit=100):
    """Find issues matching criteria using gh CLI."""

    # Build search query
    query_parts = [f"repo:{repo}"]

    if state:
        query_parts.append(f"is:{state}")

    if label:
        query_parts.append(f"label:{label}")

    query = " ".join(query_parts)

    # Fetch issues using gh CLI
    cmd = f"""gh issue list \
        --repo {repo} \
        --search '{query}' \
        --limit {limit} \
        --json number,title,state,labels,createdAt,updatedAt \
        --jq '.'"""

    result = run_command(cmd)

    if result.returncode != 0:
        print(f"Error fetching issues: {result.stderr}", file=sys.stderr)
        return []

    try:
        issues = json.loads(result.stdout)
        return issues
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        return []


def fetch_issue_complete(repo, issue_number, output_dir):
    """Fetch complete issue data using fetch-issue-complete.py."""

    # Locate fetch-issue-complete.py script
    script_paths = [
        ".ai-tools-resources/scripts/github-utils/fetch-issue-complete.py",
        "scripts/github-utils/fetch-issue-complete.py",
        "/tmp/fetch-issue-complete.py"
    ]

    script = None
    for path in script_paths:
        if os.path.exists(path):
            script = path
            break

    if not script:
        print(f"ERROR: fetch-issue-complete.py not found", file=sys.stderr)
        return False

    # Create issue-specific output directory
    issue_dir = Path(output_dir) / str(issue_number)
    issue_dir.mkdir(parents=True, exist_ok=True)

    # Fetch complete issue data
    cmd = f"python3 {script} {repo} {issue_number} {issue_dir}"
    result = run_command(cmd, capture_output=False)

    return result.returncode == 0


def create_manifest(issues, output_dir):
    """Create manifest file with summary of all issues."""

    manifest = {
        "total_issues": len(issues),
        "issues": []
    }

    for issue in issues:
        manifest["issues"].append({
            "number": issue["number"],
            "title": issue["title"],
            "state": issue["state"],
            "labels": [label["name"] for label in issue.get("labels", [])],
            "created_at": issue.get("createdAt"),
            "updated_at": issue.get("updatedAt"),
            "data_dir": str(issue["number"])
        })

    manifest_path = Path(output_dir) / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"Created manifest: {manifest_path}")
    return manifest_path


def main():
    parser = argparse.ArgumentParser(
        description="Fetch issues matching criteria with complete data"
    )
    parser.add_argument("repo", help="Repository (OWNER/REPO)")
    parser.add_argument(
        "--label",
        help="Filter by label"
    )
    parser.add_argument(
        "--state",
        default="open",
        choices=["open", "closed", "all"],
        help="Issue state (default: open)"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Maximum issues to fetch (default: 100)"
    )
    parser.add_argument(
        "--output-dir",
        default="issues",
        help="Output directory (default: issues)"
    )

    args = parser.parse_args()

    # Validate environment
    if not os.getenv("GITHUB_TOKEN") and not os.getenv("GH_TOKEN"):
        print("ERROR: GITHUB_TOKEN or GH_TOKEN required", file=sys.stderr)
        sys.exit(1)

    print(f"Fetching issues from {args.repo}")
    print(f"  Label: {args.label or 'any'}")
    print(f"  State: {args.state}")
    print(f"  Limit: {args.limit}")
    print()

    # Find matching issues
    issues = fetch_matching_issues(
        args.repo,
        label=args.label,
        state=args.state,
        limit=args.limit
    )

    if not issues:
        print("No issues found matching criteria")

        # Create empty manifest
        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        create_manifest([], args.output_dir)
        sys.exit(0)

    print(f"Found {len(issues)} issues")
    print()

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Fetch complete data for each issue
    success_count = 0
    fail_count = 0

    for issue in issues:
        number = issue["number"]
        title = issue["title"]

        print(f"Fetching issue #{number}: {title}")

        if fetch_issue_complete(args.repo, number, args.output_dir):
            success_count += 1
            print(f"  ✓ Complete")
        else:
            fail_count += 1
            print(f"  ✗ Failed")

        print()

    # Create manifest
    create_manifest(issues, args.output_dir)

    print(f"Summary:")
    print(f"  Total issues: {len(issues)}")
    print(f"  Successful: {success_count}")
    print(f"  Failed: {fail_count}")
    print(f"  Output directory: {output_dir.absolute()}")

    sys.exit(0 if fail_count == 0 else 1)


if __name__ == "__main__":
    main()
