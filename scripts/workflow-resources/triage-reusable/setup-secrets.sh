#!/usr/bin/env bash
set -e

# Create directory for secrets in tmp
mkdir -p /tmp/ai-tools

# Convert secrets to JSON and mask them
SECRETS_JSON="${SECRETS_JSON:-}"

# Mask the entire JSON string
echo "::add-mask::$SECRETS_JSON"

# Write masked secrets to file
echo "$SECRETS_JSON" > /tmp/ai-tools/secrets.json
chmod 644 /tmp/ai-tools/secrets.json

# Create Python helper script for secure secret retrieval
cat << 'PYTHON_SCRIPT' > /tmp/ai-tools/get-secret.py
#!/usr/bin/env python3
"""
Secure secret retrieval utility for AI Tools hooks
"""
import json
import sys
import os

def get_secret(secret_name):
    """Retrieve a secret by name from the secrets file"""
    secrets_file = '/tmp/ai-tools/secrets.json'

    if not os.path.exists(secrets_file):
        print(f"Error: Secrets file not found at {secrets_file}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(secrets_file, 'r') as f:
            secrets = json.load(f)

        if secret_name in secrets:
            print(secrets[secret_name], end='')
            return 0
        else:
            print(f"Warning: Secret '{secret_name}' not found", file=sys.stderr)
            return 1

    except Exception as e:
        print(f"Error reading secrets: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 /tmp/ai-tools/get-secret.py SECRET_NAME", file=sys.stderr)
        sys.exit(1)

    secret_name = sys.argv[1]
    exit_code = get_secret(secret_name)
    sys.exit(exit_code)
PYTHON_SCRIPT

chmod 755 /tmp/ai-tools/get-secret.py
echo "✅ Secrets helper created"
