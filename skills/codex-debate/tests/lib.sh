#!/usr/bin/env bash
# lib.sh — Shared functions for codex-debate skill
# Extracted for unit testing. The debate.md command uses equivalent inline logic.
set -euo pipefail

# ============================================================
# mask_secrets — Replace known secret patterns with [REDACTED]
# Usage: echo "text" | mask_secrets
# ============================================================
mask_secrets() {
  sed -E \
    -e 's/AKIA[A-Z0-9]{16}/[REDACTED:AWS_KEY]/g' \
    -e 's/(api_key|api_secret|token|secret|password|auth_token|access_key|private_key)([[:space:]]*[:=][[:space:]]*)("([^"]*)"|'"'"'([^'"'"']*)'"'"'|[^[:space:],;]+)/\1\2[REDACTED]/gi' \
    -e 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED:GH_TOKEN]/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED:API_KEY]/g' \
    -e 's/\b[A-Za-z0-9+\/]{60,}={0,2}\b/[REDACTED:LONG_SECRET]/g'
}

# ============================================================
# parse_args — Parse debate command arguments
# Usage: parse_args "topic" --rounds 3
# Returns: TOPIC, ROUNDS as exported variables
# ============================================================
parse_args() {
  TOPIC=""
  ROUNDS=3

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rounds)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --rounds requires a value" >&2; return 1
        fi
        ROUNDS="$2"
        shift 2
        ;;
      --*)
        echo "ERROR: Unknown flag '$1'" >&2; return 1
        ;;
      *)
        # Non-flag arguments are concatenated into the topic (strip quotes)
        local word="${1//\"/}"
        if [[ -n "$word" ]]; then
          if [[ -z "$TOPIC" ]]; then
            TOPIC="$word"
          else
            TOPIC="$TOPIC $word"
          fi
        fi
        shift
        ;;
    esac
  done

  # Validate rounds (input must be 1-10)
  if ! [[ "$ROUNDS" =~ ^[0-9]+$ ]] || [[ "$ROUNDS" -lt 1 ]] || [[ "$ROUNDS" -gt 10 ]]; then
    echo "ERROR: Rounds must be integer 1-10, got '$ROUNDS'" >&2
    return 1
  fi

  # Ensure rounds is odd (Codex always has final word)
  # If even, decrement to previous odd (not increment, to stay within 1-10)
  if (( ROUNDS % 2 == 0 )); then
    ROUNDS=$(( ROUNDS - 1 ))
  fi

  # Safety clamp (should not be needed, but defensive)
  if (( ROUNDS < 1 )); then ROUNDS=1; fi

  # Validate topic
  if [[ -z "$TOPIC" ]]; then
    echo "ERROR: Topic is required" >&2
    return 1
  fi

  export TOPIC ROUNDS
}

# ============================================================
# collect_context — Auto-gather project context (git diff + structure)
# Usage: collect_context [--max-chars 2000]
# Returns: CONTEXT_SUMMARY, CONTEXT_DIFF_LINES
# ============================================================
collect_context() {
  local max_chars=2000

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-chars)
        if [[ $# -lt 2 ]]; then echo "ERROR: --max-chars requires a value" >&2; return 1; fi
        max_chars="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local context=""
  local diff_lines=0

  # Auto-collect git diff (staged → working tree → last commit)
  local diff_content=""
  diff_content=$(git diff --staged 2>/dev/null || true)
  if [[ -z "$diff_content" ]]; then
    diff_content=$(git diff 2>/dev/null || true)
  fi
  if [[ -z "$diff_content" ]]; then
    diff_content=$(git diff HEAD~1 HEAD 2>/dev/null || true)
  fi

  if [[ -n "$diff_content" ]]; then
    diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
    context=$(echo "$diff_content" | head -200)
  fi

  # Auto-collect project structure overview
  local structure=""
  structure=$(git ls-files 2>/dev/null | head -30 || true)
  if [[ -n "$structure" ]]; then
    context="$(printf '%s\n\n## Project Structure (top 30 tracked files)\n%s' "$context" "$structure")"
  fi

  # Apply secret masking
  context=$(printf '%s' "$context" | mask_secrets)

  # Truncate if needed
  local char_count=${#context}
  if (( char_count > max_chars )); then
    context="$(printf '%s\n[... truncated: %d chars total, showing first %d]' "${context:0:$max_chars}" "$char_count" "$max_chars")"
  fi

  CONTEXT_SUMMARY="$context"
  CONTEXT_DIFF_LINES="$diff_lines"
  export CONTEXT_SUMMARY CONTEXT_DIFF_LINES
}

# ============================================================
# generate_slug — Create URL-safe slug from text
# Usage: generate_slug "My Topic Here"
# Returns: my-topic-here
# ============================================================
generate_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//' | head -c 50
}

# ============================================================
# save_debate — Save final debate artifact
# Usage: save_debate <topic> <rounds> <outcome> <confidence> <summary_md> <transcript_md> [<verdict_json>]
# ============================================================
save_debate() {
  local topic="$1"
  local rounds="$2"
  local outcome="${3:-unknown}"
  local confidence="${4:-0}"
  local summary_md="$5"
  local transcript_md="$6"
  local verdict_json="${7:-}"

  local slug
  slug=$(generate_slug "$topic")
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M)
  local filename="${timestamp}-${slug}.md"
  local output_dir=".claude/debates"

  mkdir -p "$output_dir"

  {
    cat <<FRONT
---
topic: "${topic}"
rounds: ${rounds}
date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
outcome: ${outcome}
confidence: ${confidence}
---

FRONT
    echo "$summary_md"
    echo ""
    echo "---"
    echo ""
    echo "# Full Transcript"
    echo ""
    echo "$transcript_md"

    if [[ -n "$verdict_json" ]]; then
      echo ""
      echo "---"
      echo ""
      echo "## Raw Verdict"
      echo ""
      echo '```json'
      echo "$verdict_json"
      echo '```'
    fi
  } > "${output_dir}/${filename}"

  echo "${output_dir}/${filename}"
}
