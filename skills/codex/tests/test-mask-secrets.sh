#!/usr/bin/env bash
# Unit tests for mask_secrets function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_not_contains() {
  local test_name="$1"
  local forbidden="$2"
  local actual="$3"
  if [[ "$actual" != *"$forbidden"* ]]; then
    echo "  PASS: $test_name"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $test_name (still contains '$forbidden')"
    echo "    actual: $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "=== mask_secrets tests ==="

# Test 1: AWS access key
result=$(echo "key=AKIAIOSFODNN7EXAMPLE" | mask_secrets)
assert_not_contains "AWS key masked" "AKIAIOSFODNN7EXAMPLE" "$result"
assert_eq "AWS key replaced with tag" "key=[REDACTED:AWS_KEY]" "$result"

# Test 2: GitHub token (ghp_)
result=$(echo "GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTuvwx" | mask_secrets)
assert_not_contains "GitHub token masked" "ghp_ABCDEF" "$result"

# Test 3: Generic api_key
result=$(echo "api_key=sk_live_abc123def456" | mask_secrets)
assert_not_contains "api_key value masked" "sk_live_abc123def456" "$result"

# Test 4: Generic token with equals
result=$(echo "token = mySecretToken123" | mask_secrets)
assert_not_contains "token value masked" "mySecretToken123" "$result"

# Test 5: Password in config
result=$(echo 'password: "hunter2"' | mask_secrets)
assert_not_contains "password masked" "hunter2" "$result"

# Test 6: OpenAI key
result=$(echo "OPENAI_API_KEY=sk-proj1234567890abcdefgh" | mask_secrets)
assert_not_contains "OpenAI key masked" "sk-proj1234567890abcdefgh" "$result"

# Test 7: Normal text not masked
result=$(echo "This is a normal commit message about tokens concept" | mask_secrets)
assert_eq "Normal text preserved" "This is a normal commit message about tokens concept" "$result"

# Test 8: Multiple secrets in one line
result=$(echo "api_key=secret123 token=abc456" | mask_secrets)
assert_not_contains "First secret masked" "secret123" "$result"
assert_not_contains "Second secret masked" "abc456" "$result"

# Test 9: Empty input
result=$(echo "" | mask_secrets)
assert_eq "Empty input returns empty" "" "$result"

# Test 10: Code that mentions secret-like words but no values
result=$(echo "func getSecretManager() { return new SecretManager() }" | mask_secrets)
# This should NOT be masked since there's no assignment pattern
echo "  INFO: Code with secret-like words (manual check): $result"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
