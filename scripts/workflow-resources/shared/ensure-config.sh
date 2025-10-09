#!/bin/bash
set -euo pipefail

# Ensure config file exists, create from baseline if needed
# This script is idempotent and safe to run multiple times
# Supports both YAML and JSON formats (YAML is recommended)

CONFIG_FILE="${CONFIG_FILE:-.github/ai-tools-config.yml}"
BASELINE_REPO="${BASELINE_REPO:-BallicomDev/ai-tools}"
BASELINE_FILE=".github/ai-tools-config.yml"

# Check if config already exists
if [[ -f "$CONFIG_FILE" ]]; then
  echo "✓ Config file already exists: $CONFIG_FILE"
  exit 0
fi

echo "Config file not found: $CONFIG_FILE"
echo "Fetching baseline from $BASELINE_REPO..."

# Create directory if needed
CONFIG_DIR=$(dirname "$CONFIG_FILE")
if [[ ! -d "$CONFIG_DIR" ]]; then
  mkdir -p "$CONFIG_DIR"
  echo "✓ Created directory: $CONFIG_DIR"
fi

# Try to fetch baseline config from GitHub using gh CLI (authenticated)
if command -v gh &>/dev/null; then
  echo "Attempting to fetch via gh CLI..."
  if gh api "repos/$BASELINE_REPO/contents/$BASELINE_FILE" --jq '.content' 2>/dev/null | base64 -d > "$CONFIG_FILE" 2>/dev/null; then
    echo "✓ Config file created from baseline: $CONFIG_FILE"
    exit 0
  else
    echo "  gh CLI fetch failed, trying direct HTTP..."
    rm -f "$CONFIG_FILE"
  fi
fi

# Fallback: Fetch baseline config from GitHub (unauthenticated)
BASELINE_URL="https://raw.githubusercontent.com/$BASELINE_REPO/main/$BASELINE_FILE"

if command -v curl &>/dev/null; then
  HTTP_CODE=$(curl -s -w "%{http_code}" -o "$CONFIG_FILE" "$BASELINE_URL")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✓ Config file created from baseline: $CONFIG_FILE"
    exit 0
  else
    echo "✗ Failed to fetch baseline via curl (HTTP $HTTP_CODE)"
    rm -f "$CONFIG_FILE"
  fi
elif command -v wget &>/dev/null; then
  if wget -q -O "$CONFIG_FILE" "$BASELINE_URL"; then
    echo "✓ Config file created from baseline: $CONFIG_FILE"
    exit 0
  else
    echo "✗ Failed to fetch baseline via wget"
    rm -f "$CONFIG_FILE"
  fi
fi

# Final fallback: Create minimal default config
echo "Creating minimal default config..."

# Detect desired format from filename
if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
  # Create YAML format
  cat > "$CONFIG_FILE" << 'EOF'
# AI Tools Configuration
# Baseline fetch failed - please update with appropriate values

default-assignee: ""
default-project-url: ""
EOF
else
  # Create JSON format
  cat > "$CONFIG_FILE" << 'EOF'
{
  "default-assignee": "",
  "default-project-url": ""
}
EOF
fi

echo "⚠ Warning: Created minimal config (baseline fetch failed)"
echo "  Please update $CONFIG_FILE with appropriate values"
exit 0
