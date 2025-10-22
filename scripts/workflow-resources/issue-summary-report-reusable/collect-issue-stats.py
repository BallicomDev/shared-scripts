#!/usr/bin/env python3
"""
Collect Issue Statistics for Summary Report
Generic script for collecting GitHub issue statistics
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

def run_gh_command(command, max_attempts=3, backoff_base=2):
    """Run gh CLI command with retry logic and return JSON result"""
    for attempt in range(1, max_attempts + 1):
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            env=os.environ
        )

        if result.returncode == 0:
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                return None

        if attempt == max_attempts:
            print(f"Error running: {command}", file=sys.stderr)
            print(f"Error: {result.stderr}", file=sys.stderr)
            return None

        wait_time = backoff_base ** attempt
        print(f"Attempt {attempt}/{max_attempts} failed (exit {result.returncode}), retrying in {wait_time}s...", file=sys.stderr)
        time.sleep(wait_time)

    return None

# Get repository info from environment
repo = os.environ.get('GITHUB_REPOSITORY', '')
if not repo:
    print("Error: GITHUB_REPOSITORY environment variable not set")
    exit(1)

print(f"Repository: {repo}")

# Get all open issues
print("Fetching open issues...")
open_issues = run_gh_command(
    f'gh api repos/{repo}/issues --paginate -q "."'
)

if not open_issues:
    open_issues = []
elif not isinstance(open_issues, list):
    open_issues = [open_issues]

# Filter out pull requests
open_issues = [i for i in open_issues if isinstance(i, dict) and 'pull_request' not in i]

# Get recently closed issues (last 7 days)
week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
print(f"Fetching issues closed since {week_ago}...")
closed_issues = run_gh_command(
    f'gh api repos/{repo}/issues?state=closed&since={week_ago} --paginate -q "."'
)

if not closed_issues:
    closed_issues = []
elif not isinstance(closed_issues, list):
    closed_issues = [closed_issues]

# Filter out pull requests
closed_issues = [i for i in closed_issues if isinstance(i, dict) and 'pull_request' not in i]

# Calculate statistics
stats = {
    "repository": repo,
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "open_issues": {
        "total": len(open_issues),
        "by_priority": {
            "critical": 0,
            "high": 0,
            "medium": 0,
            "low": 0,
            "unprioritized": 0
        },
        "by_age": {
            "new": 0,  # < 24 hours
            "recent": 0,  # 1-7 days
            "active": 0,  # 7-30 days
            "stale": 0,  # 30-90 days
            "ancient": 0  # > 90 days
        },
        "by_area": {},
        "with_bug_label": 0,
        "with_enhancement_label": 0
    },
    "closed_last_7_days": {
        "total": len(closed_issues),
        "average_time_to_close_hours": 0
    },
    "issues": {
        "open": [],
        "recently_closed": []
    }
}

# Process open issues
now = datetime.now(timezone.utc)
for issue in open_issues:
    created = datetime.fromisoformat(issue['created_at'].replace('Z', '+00:00'))
    age_days = (now - created).days

    # Extract priority
    priority = "unprioritized"
    for label in issue.get('labels', []):
        label_name = label['name'].lower()
        if 'critical' in label_name:
            priority = "critical"
            break
        elif 'high' in label_name:
            priority = "high"
        elif 'medium' in label_name and priority == "unprioritized":
            priority = "medium"
        elif 'low' in label_name and priority == "unprioritized":
            priority = "low"

    stats["open_issues"]["by_priority"][priority] += 1

    # Categorize by age
    if age_days < 1:
        stats["open_issues"]["by_age"]["new"] += 1
    elif age_days <= 7:
        stats["open_issues"]["by_age"]["recent"] += 1
    elif age_days <= 30:
        stats["open_issues"]["by_age"]["active"] += 1
    elif age_days <= 90:
        stats["open_issues"]["by_age"]["stale"] += 1
    else:
        stats["open_issues"]["by_age"]["ancient"] += 1

    # Count by area and type
    for label in issue.get('labels', []):
        label_name = label['name'].lower()
        if label_name.startswith('area:'):
            area = label_name.replace('area:', '').strip()
            stats["open_issues"]["by_area"][area] = stats["open_issues"]["by_area"].get(area, 0) + 1
        if label_name == 'bug':
            stats["open_issues"]["with_bug_label"] += 1
        if label_name == 'enhancement':
            stats["open_issues"]["with_enhancement_label"] += 1

    # Add to issues list
    stats["issues"]["open"].append({
        "number": issue['number'],
        "title": issue['title'],
        "url": issue['html_url'],
        "created_at": issue['created_at'],
        "age_days": age_days,
        "priority": priority,
        "labels": [l['name'] for l in issue.get('labels', [])]
    })

# Process closed issues
total_close_time = 0
closed_with_time = 0
for issue in closed_issues:
    if issue.get('closed_at'):
        created = datetime.fromisoformat(issue['created_at'].replace('Z', '+00:00'))
        closed = datetime.fromisoformat(issue['closed_at'].replace('Z', '+00:00'))
        time_to_close = (closed - created).total_seconds() / 3600  # in hours
        total_close_time += time_to_close
        closed_with_time += 1

        stats["issues"]["recently_closed"].append({
            "number": issue['number'],
            "title": issue['title'],
            "url": issue['html_url'],
            "closed_at": issue['closed_at'],
            "time_to_close_hours": round(time_to_close, 1)
        })

if closed_with_time > 0:
    stats["closed_last_7_days"]["average_time_to_close_hours"] = round(total_close_time / closed_with_time, 1)

# Output directory from environment or default
output_dir = os.environ.get('OUTPUT_DIR', '/tmp/issue-data')
os.makedirs(output_dir, exist_ok=True)

# Save statistics
stats_file = os.path.join(output_dir, 'stats.json')
with open(stats_file, 'w') as f:
    json.dump(stats, f, indent=2)

# Create summary for output
print(f"\n=== Issue Statistics ===")
print(f"Open Issues: {stats['open_issues']['total']}")
print(f"  Critical: {stats['open_issues']['by_priority']['critical']}")
print(f"  High: {stats['open_issues']['by_priority']['high']}")
print(f"  Medium: {stats['open_issues']['by_priority']['medium']}")
print(f"  Low: {stats['open_issues']['by_priority']['low']}")
print(f"  Unprioritized: {stats['open_issues']['by_priority']['unprioritized']}")
print(f"\nClosed Last 7 Days: {stats['closed_last_7_days']['total']}")
if stats['closed_last_7_days']['average_time_to_close_hours'] > 0:
    print(f"  Average Time to Close: {stats['closed_last_7_days']['average_time_to_close_hours']} hours")

print(f"\nStatistics saved to: {stats_file}")