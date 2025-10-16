#!/bin/bash
# Config file helper functions
# Supports both JSON and YAML formats

get_config_value() {
  # Read config key with optional default fallback
  # Args:
  #   $1: config file path (default: .github/ai-tools-config.yml)
  #   $2: config key name
  #   $3: default value (optional)
  # Returns:
  #   Config value or default

  local config_file="${1:-.github/ai-tools-config.yml}"
  local key="$2"
  local default="${3:-}"

  if [[ ! -f "$config_file" ]]; then
    echo "$default"
    return 0
  fi

  # Detect format and use appropriate tool
  local value
  if [[ "$config_file" =~ \.ya?ml$ ]]; then
    # YAML format - use yq if available, fallback to grep/awk
    if command -v yq &>/dev/null; then
      value=$(yq eval ".$key" "$config_file" 2>/dev/null)
      if [[ "$value" == "null" || -z "$value" ]]; then
        value="$default"
      fi
    else
      # Fallback: simple grep/awk parsing for top-level keys only
      value=$(grep "^${key}:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' 2>/dev/null)
      if [[ -z "$value" ]]; then
        value="$default"
      fi
    fi
  else
    # JSON format - use jq
    value=$(jq -r ".\"$key\" // \"$default\"" "$config_file" 2>/dev/null)
    if [[ $? -ne 0 || -z "$value" || "$value" == "null" ]]; then
      value="$default"
    fi
  fi

  echo "$value"
}

get_default_assignee() {
  # Get default assignee from config
  # Args:
  #   $1: config file path (optional, defaults to .github/ai-tools-config.yml)
  # Returns:
  #   Default assignee username or empty string

  get_config_value "${1:-.github/ai-tools-config.yml}" "default-assignee" ""
}

export -f get_config_value
export -f get_default_assignee
