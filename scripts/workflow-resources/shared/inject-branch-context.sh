#!/bin/bash
# Append branch-analysis context to a prompt file when analysing a non-default ref.
#
# The caller decides whether to run this (only on non-default refs); this script
# just appends a guidance block naming the analysed branch so the model treats
# "absent in this checkout" as "not on this branch" rather than "wrong repo".
#
# Args:
#   $1  path to the prompt file to append to (must already exist; a missing
#       file is a no-op so a skipped prompt-prep step cannot error the run)
# Env:
#   TARGET_BRANCH  the ref that was checked out (required)
#
# The branch name is only ever expanded inside double-quoted shell here, never
# through stream editors or eval, so a name with metacharacters cannot corrupt
# the prompt.

set -euo pipefail

PROMPT_FILE="${1:?prompt file path required}"
: "${TARGET_BRANCH:?TARGET_BRANCH required}"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Prompt file '$PROMPT_FILE' not found; skipping branch context injection."
  exit 0
fi

# Actual checked-out commit (tip of the branch), for display only.
TARGET_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

{
  echo ""
  echo "## Branch context"
  echo ""
  echo "You are analysing this repository at ref: \`${TARGET_BRANCH}\` (commit \`${TARGET_SHA}\`)."
  echo "This is NOT the default branch. Code can exist on other branches that are not present in this checkout."
  echo ""
  echo "Rules for judging whether something exists or is relevant:"
  echo "- If a file, symbol, or feature is not found in this checkout, report it as \"not found on \`${TARGET_BRANCH}\`\" - never as \"does not exist in this project\"."
  echo "- Do NOT conclude the issue belongs to the wrong repository when the only evidence is that a feature is absent here. A feature that exists only on a release or feature branch is VALID and RELEVANT - it is in development, not fictional."
  echo "- Any \"wrong repository\" or \"does not exist\" conclusion MUST cite the exact searches you ran (the globs/greps and paths you checked)."
  echo "- State the analysed branch in your comment, and when you link source code use the branch where the code actually exists."
  echo "- If you create a branch or base any code changes on this repository, branch from \`${TARGET_BRANCH}\` (the branch under test), not the default branch."
} >> "$PROMPT_FILE"

echo "Injected branch context for ref '${TARGET_BRANCH}' into $PROMPT_FILE"
