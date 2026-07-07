#!/usr/bin/env python3
"""
Parse a vague reset clock string (e.g. "5pm") into the next future ISO-8601
UTC timestamp.

The bare hour is interpreted as UTC (the execution environment runs in UTC).

Usage:
    python parse-reset-time.py "5pm" [--now 2026-07-06T16:04:00+00:00]

On success: prints the ISO-8601 UTC timestamp to stdout, exit 0.
On unparseable input: prints nothing to stdout, writes a reason to stderr,
exit code 3.
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timedelta, timezone

_TIME_RE = re.compile(r"^(?P<hour>\d{1,2})(?::(?P<minute>\d{2}))?\s*(?P<ampm>am|pm)?$")


def parse_reset_time(raw: str, now: datetime) -> datetime | None:
    """Parse `raw` as a UTC wall-clock time and return the next occurrence
    strictly after `now`. Returns None if `raw` cannot be parsed."""
    cleaned = raw.strip().lower()
    match = _TIME_RE.match(cleaned)
    if match is None:
        return None

    hour = int(match.group("hour"))
    minute_str = match.group("minute")
    minute = int(minute_str) if minute_str is not None else 0
    ampm = match.group("ampm")

    if ampm is not None:
        if not (1 <= hour <= 12):
            return None
        is_noon_or_midnight = hour == 12
        if ampm == "am":
            hour = 0 if is_noon_or_midnight else hour
        elif not is_noon_or_midnight:
            hour = hour + 12
    else:
        if not (0 <= hour <= 23):
            return None

    if not (0 <= minute <= 59):
        return None

    candidate = now.astimezone(timezone.utc).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    )
    if candidate <= now:
        candidate += timedelta(days=1)
    return candidate


def _parse_now_arg(value: str) -> datetime:
    normalised = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalised)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Parse a bare clock string into the next future UTC ISO-8601 timestamp."
    )
    parser.add_argument("resets_raw", help='Bare clock string, e.g. "5pm"')
    parser.add_argument(
        "--now",
        dest="now",
        default=None,
        help="ISO-8601 timestamp to use as the reference 'now' (defaults to current UTC time)",
    )
    args = parser.parse_args()

    if args.now is not None:
        try:
            now = _parse_now_arg(args.now)
        except ValueError as exc:
            print(
                f"error: could not parse --now value {args.now!r}: {exc}",
                file=sys.stderr,
            )
            return 3
    else:
        now = datetime.now(timezone.utc)

    result = parse_reset_time(args.resets_raw, now)
    if result is None:
        print(
            f"error: could not parse reset time from {args.resets_raw!r}",
            file=sys.stderr,
        )
        return 3

    print(result.isoformat())
    return 0


if __name__ == "__main__":
    sys.exit(main())
