#!/bin/bash
# Issue creation helper functions with config integration

# Source config helpers if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config-helpers.sh" ]]; then
  source "$SCRIPT_DIR/config-helpers.sh"
fi

create_issue_with_defaults() {
  # Create issue with default assignee from config
  # Args: Same as gh issue create, plus:
  #   --config: Config file path (optional, default: .github/ai-tools-config.yml)
  # Example:
  #   create_issue_with_defaults --repo owner/repo --title "Title" --body "Body" --label "bug"

  local config_file=".github/ai-tools-config.yml"
  local gh_args=()

  # Parse arguments, extract --config if present
  while [[ $# -gt 0 ]]; do
    case $1 in
      --config)
        config_file="$2"
        shift 2
        ;;
      *)
        gh_args+=("$1")
        shift
        ;;
    esac
  done

  # Get default assignee from config
  local assignee
  if type get_default_assignee &>/dev/null; then
    assignee=$(get_default_assignee "$config_file")
  fi

  # Build gh issue create command
  local cmd=(gh issue create "${gh_args[@]}")

  # Add assignee if found
  if [[ -n "$assignee" ]]; then
    cmd+=(--assignee "$assignee")
  fi

  # Execute
  "${cmd[@]}"
}

export -f create_issue_with_defaults
