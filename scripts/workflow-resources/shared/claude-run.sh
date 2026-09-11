#!/usr/bin/env bash
# Credential-rotating runner for the CLI.
#
# Source this file, then call claude_run_with_failover instead of invoking the
# CLI directly:
#
#   source "<resources>/scripts/workflow-resources/shared/claude-run.sh"
#   claude_run_with_failover /tmp/output.json -p "$PROMPT" --model "$MODEL" ...
#   exit_code=$?
#
# Credentials are discovered from the environment: CLAUDE_CODE_OAUTH_TOKEN,
# CLAUDE_CODE_OAUTH_TOKEN_2, CLAUDE_CODE_OAUTH_TOKEN_3, and so on. Unset or
# empty slots are skipped, so a caller that only has one still works and a gap
# in the middle of the numbering is harmless.
#
# The starting slot rotates, so load is spread rather than always landing on
# the first credential. Seed it with a per-run value (a run id) via
# CLAUDE_ROTATION_SEED; it falls back to the clock.
#
# On a capacity rejection the same invocation is retried against the next
# credential. Return value:
#   0..74, 76+  the CLI's own exit code from the attempt that ran
#   75          every available credential was rejected for capacity

CLAUDE_CAPACITY_EXHAUSTED_RC=75

# Number of slots probed. Well above any plausible credential count; probing a
# slot that does not exist costs nothing.
CLAUDE_CREDENTIAL_MAX_SLOTS="${CLAUDE_CREDENTIAL_MAX_SLOTS:-8}"

# Set by claude_run_with_failover for the caller to inspect after it returns.
export CLAUDE_RUN_CLASSIFICATION=""
export CLAUDE_RUN_RESETS_AT_EPOCH=""
export CLAUDE_RUN_RESETS_RAW=""
export CLAUDE_RUN_LIMIT_TYPE=""
export CLAUDE_RUN_SLOTS_TRIED=0

_claude_run_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Echo one credential value per line, in slot order, skipping empty slots.
claude_collect_credentials() {
  local prefix="${CLAUDE_CREDENTIAL_PREFIX:-CLAUDE_CODE_OAUTH_TOKEN}"
  local value name index

  value="${!prefix:-}"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  fi

  for (( index=2; index<=CLAUDE_CREDENTIAL_MAX_SLOTS; index++ )); do
    name="${prefix}_${index}"
    value="${!name:-}"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
    fi
  done
}

claude_run_with_failover() {
  local capture_file="$1"
  shift

  local prefix="${CLAUDE_CREDENTIAL_PREFIX:-CLAUDE_CODE_OAUTH_TOKEN}"
  local classifier
  classifier="$(_claude_run_dir)/classify-outcome.py"

  local -a credentials=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && credentials+=("$line")
  done < <(claude_collect_credentials)

  local total=${#credentials[@]}
  if [ "$total" -eq 0 ]; then
    echo "ERROR: no credential available (${prefix} is unset or empty)" >&2
    return 1
  fi

  local seed="${CLAUDE_ROTATION_SEED:-$(date +%s)}"
  # Strip anything non-numeric so a caller can pass an id without sanitising.
  seed="${seed//[^0-9]/}"
  [ -n "$seed" ] || seed=0
  local start=$(( seed % total ))

  local attempt index exit_code=1 classification="other_failure" class_json=""
  local all_exhausted=1

  CLAUDE_RUN_SLOTS_TRIED=0

  for (( attempt=0; attempt<total; attempt++ )); do
    index=$(( (start + attempt) % total ))
    echo "CLI attempt $((attempt + 1)) of ${total} (credential slot ${index})"
    CLAUDE_RUN_SLOTS_TRIED=$((attempt + 1))

    export "${prefix}=${credentials[$index]}"

    claude "$@" 2>&1 | tee "$capture_file"
    exit_code=${PIPESTATUS[0]}

    class_json="$(python3 "$classifier" "$capture_file" ${CLAUDE_ACTION_MARKER:+--action-marker "$CLAUDE_ACTION_MARKER"})"
    classification="$(printf '%s' "$class_json" | jq -r '.classification')"
    CLAUDE_RUN_CLASSIFICATION="$classification"
    CLAUDE_RUN_RESETS_AT_EPOCH="$(printf '%s' "$class_json" | jq -r '.resets_at_epoch // empty')"
    CLAUDE_RUN_RESETS_RAW="$(printf '%s' "$class_json" | jq -r '.resets_raw // empty')"
    CLAUDE_RUN_LIMIT_TYPE="$(printf '%s' "$class_json" | jq -r '.limit_type // empty')"

    echo "Outcome classification: ${classification}${CLAUDE_RUN_LIMIT_TYPE:+ (${CLAUDE_RUN_LIMIT_TYPE})}"

    if [ "$classification" = "capacity_exhausted" ]; then
      echo "Credential slot ${index} was rejected for capacity; trying the next slot if one remains"
      continue
    fi

    all_exhausted=0
    break
  done

  if [ "$all_exhausted" -eq 1 ]; then
    echo "All ${total} credential(s) were rejected for capacity"
    return "$CLAUDE_CAPACITY_EXHAUSTED_RC"
  fi

  return "$exit_code"
}
