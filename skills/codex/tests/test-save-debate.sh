#!/usr/bin/env bash
# Unit tests for save_debate and generate_slug functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PASS=0
FAIL=0

# Use temp directory for test isolation
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

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

assert_file_exists() {
  local test_name="$1"
  local filepath="$2"
  if [[ -f "$filepath" ]]; then
    echo "  PASS: $test_name"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $test_name (file not found: $filepath)"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_file_contains() {
  local test_name="$1"
  local filepath="$2"
  local pattern="$3"
  if grep -q "$pattern" "$filepath" 2>/dev/null; then
    echo "  PASS: $test_name"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $test_name (pattern '$pattern' not found in $filepath)"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "=== generate_slug tests ==="

# Test 1: Basic slug
result=$(generate_slug "My Architecture Decision")
assert_eq "Basic slug" "my-architecture-decision" "$result"

# Test 2: Special characters
result=$(generate_slug "Should we use React.js?!")
assert_eq "Special chars removed" "should-we-use-react-js" "$result"

# Test 3: Already lowercase
result=$(generate_slug "simple topic")
assert_eq "Lowercase preserved" "simple-topic" "$result"

# Test 4: Long topic truncated
result=$(generate_slug "This is a very long topic that should be truncated to fifty characters maximum")
len=${#result}
if (( len <= 50 )); then
  echo "  PASS: Slug truncated to ≤50 chars (got $len)"
  (( PASS++ ))
else
  echo "  FAIL: Slug too long ($len chars)"
  (( FAIL++ ))
fi

# Test 5: Numbers preserved
result=$(generate_slug "RFC 4122 UUID generation")
assert_eq "Numbers preserved" "rfc-4122-uuid-generation" "$result"

echo ""
echo "=== save_debate tests ==="

# Test 6: Basic save
output_path=$(save_debate \
  "Test Topic" \
  "3" \
  "approve" \
  "8" \
  "## Summary\nDecision approved." \
  "## Round 0\nProposal here." \
  '{"outcome":"approve","confidence":8}')

assert_file_exists "Debate file created" "$output_path"

# Test 7: Frontmatter present
assert_file_contains "Has topic in frontmatter" "$output_path" "topic: \"Test Topic\""
assert_file_contains "Has outcome in frontmatter" "$output_path" "outcome: approve"

# Test 8: Content sections present
assert_file_contains "Has summary" "$output_path" "Summary"
assert_file_contains "Has transcript header" "$output_path" "Full Transcript"
assert_file_contains "Has verdict JSON" "$output_path" '"outcome":"approve"'

# Test 9: Output directory created
assert_file_exists "Debates dir exists" ".claude/debates/$(basename "$output_path")"

# Test 10: Save without verdict JSON
output_path2=$(save_debate \
  "No Verdict Topic" \
  "1" \
  "reject" \
  "3" \
  "## Summary\nRejected." \
  "## Round 0\nProposal." \
  "")

assert_file_exists "File without verdict created" "$output_path2"

# Verify no "Raw Verdict" section when JSON is empty
if grep -q "Raw Verdict" "$output_path2" 2>/dev/null; then
  echo "  FAIL: No verdict section should be absent when JSON empty"
  (( FAIL++ ))
else
  echo "  PASS: No verdict section when JSON empty"
  (( PASS++ ))
fi

# Test 11: Save with recommend outcome (research topic)
output_path3=$(save_debate \
  "Best practices for caching" \
  "3" \
  "recommend" \
  "7" \
  "## Summary\nRecommend Redis with write-through." \
  "## Round 0\nProposal." \
  '{"outcome":"recommend","confidence":7}')

assert_file_exists "Recommend outcome file created" "$output_path3"
assert_file_contains "Has recommend in frontmatter" "$output_path3" "outcome: recommend"
assert_file_contains "Has recommend in verdict JSON" "$output_path3" '"outcome":"recommend"'

# Test 12: File path format
filename=$(basename "$output_path")
if [[ "$filename" =~ ^[0-9]{8}-[0-9]{4}-[a-z0-9-]+\.md$ ]]; then
  echo "  PASS: Filename matches YYYYMMDD-HHMM-slug.md format"
  (( PASS++ ))
else
  echo "  FAIL: Filename format mismatch: $filename"
  (( FAIL++ ))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
