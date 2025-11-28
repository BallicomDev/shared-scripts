#!/bin/bash
# Shared Claude CLI installation script with retry logic
# Usage: bash install-claude-cli.sh [VERSION]
# Default version: 1.0.100

set -e

VERSION="${1:-1.0.100}"

echo "Installing Claude CLI ${VERSION}..."

# Retry logic: 3 attempts with exponential backoff
MAX_ATTEMPTS=3
ATTEMPT=1
BACKOFF=2

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "Installation attempt $ATTEMPT of $MAX_ATTEMPTS..."

  if curl -fsSL https://claude.ai/install.sh | bash -s "$VERSION"; then
    echo "✓ Claude CLI installed successfully"
    echo "  Location: ~/.local/bin/claude"
    exit 0
  fi

  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    echo "⚠ Installation failed, retrying in ${BACKOFF}s..."
    sleep $BACKOFF
    BACKOFF=$((BACKOFF * 2))
    ATTEMPT=$((ATTEMPT + 1))
  else
    echo "✗ Installation failed after $MAX_ATTEMPTS attempts"
    exit 1
  fi
done
