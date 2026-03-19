#!/bin/bash
# Verify a deployed contract on Blockscout
#
# Usage:
#   ./verify.sh <contract_address> <contract_name>
#
# Example:
#   ./verify.sh 0xCa9aDc8736d5fb1743939cA745824fB8fBd97793 EpixAirdrop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Args
CONTRACT_ADDR="${1:-}"
CONTRACT_NAME="${2:-}"

if [[ -z "$CONTRACT_ADDR" || -z "$CONTRACT_NAME" ]]; then
    echo "Usage: $0 <contract_address> <contract_name>"
    echo "Example: $0 0xCa9aDc8736d5fb1743939cA745824fB8fBd97793 EpixAirdrop"
    exit 1
fi

# Explorer URL — strip trailing slash, ensure https
EXPLORER="${EXPLORER_URL:-https://testscan.epix.zone}"
EXPLORER="${EXPLORER%/}"
EXPLORER="${EXPLORER/http:/https:}"

# Detect compiler version from build artifacts
COMPILER_VERSION=""
ARTIFACT="$SCRIPT_DIR/out/${CONTRACT_NAME}.sol/${CONTRACT_NAME}.json"
if [[ -f "$ARTIFACT" ]] && command -v python3 &>/dev/null; then
    COMPILER_VERSION=$(python3 -c "
import json
with open('$ARTIFACT') as f:
    d = json.load(f)
m = d.get('metadata', d)
if isinstance(m, str):
    m = json.loads(m)
print('v' + m['compiler']['version'])
" 2>/dev/null || true)
fi

if [[ -z "$COMPILER_VERSION" ]]; then
    echo "Could not detect compiler version from artifacts. Building first..."
fi

echo "==> Building standard JSON input for $CONTRACT_NAME..."

# Build the project first to ensure artifacts are fresh
cd "$SCRIPT_DIR"
forge build --force --silent

# Re-detect compiler version after build if needed
if [[ -z "$COMPILER_VERSION" ]] && [[ -f "$ARTIFACT" ]] && command -v python3 &>/dev/null; then
    COMPILER_VERSION=$(python3 -c "
import json
with open('$ARTIFACT') as f:
    d = json.load(f)
m = d.get('metadata', d)
if isinstance(m, str):
    m = json.loads(m)
print('v' + m['compiler']['version'])
" 2>/dev/null || true)
fi

if [[ -z "$COMPILER_VERSION" ]]; then
    echo "ERROR: Could not detect compiler version"
    exit 1
fi

# Generate standard JSON input
TMPFILE=$(mktemp /tmp/verify_input_XXXXXX.json)
forge verify-contract "$CONTRACT_ADDR" "src/${CONTRACT_NAME}.sol:${CONTRACT_NAME}" \
    --show-standard-json-input > "$TMPFILE" 2>/dev/null

echo "==> Submitting to Blockscout at $EXPLORER..."
echo "    Contract: $CONTRACT_ADDR"
echo "    Name: $CONTRACT_NAME"
echo "    Compiler: $COMPILER_VERSION"
echo ""

# Submit via Blockscout v2 API
RESPONSE=$(curl -s -X POST \
    "${EXPLORER}/api/v2/smart-contracts/${CONTRACT_ADDR}/verification/via/standard-input" \
    -F "compiler_version=${COMPILER_VERSION}" \
    -F "license_type=mit" \
    -F "files[0]=@${TMPFILE};type=application/json")

rm -f "$TMPFILE"

# Check result
if command -v jq &>/dev/null; then
    VERIFIED=$(echo "$RESPONSE" | jq -r '.is_verified // empty' 2>/dev/null)
    if [[ "$VERIFIED" == "true" ]]; then
        echo "==> Verified successfully!"
        echo "$RESPONSE" | jq '{is_verified, is_fully_verified, name, compiler_version, verified_at}'
    else
        echo "==> Verification response:"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo "==> Response (install jq for prettier output):"
    echo "$RESPONSE"
fi

echo ""
echo "    View: ${EXPLORER}/address/${CONTRACT_ADDR}"
