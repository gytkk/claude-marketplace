#!/usr/bin/env bash
# stream-progress.sh: Format Codex JSONL events for human-readable progress
# Usage: codex exec --json ... | stream-progress.sh
#
# Reads JSONL from stdin and outputs formatted progress lines.
# Filters out noise, showing only meaningful events.

set -euo pipefail

while IFS= read -r line; do
  type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue
  [ -z "$type" ] && continue

  case "$type" in
    thread.started)
      echo "[codex] Session started"
      ;;
    turn.started)
      echo "[codex] --- Turn started ---"
      ;;
    turn.completed)
      tokens=$(echo "$line" | jq -r '(.usage.total_tokens // 0)' 2>/dev/null)
      echo "[codex] --- Turn completed (${tokens} tokens) ---"
      ;;
    item.created|item.completed)
      item_type=$(echo "$line" | jq -r '.item.type // empty' 2>/dev/null)
      case "$item_type" in
        agent_message)
          text=$(echo "$line" | jq -r '.item.text // empty' 2>/dev/null)
          if [ -n "$text" ]; then
            preview=$(echo "$text" | head -c 200)
            echo "[codex] Message: ${preview}"
          fi
          ;;
        reasoning)
          summary=$(echo "$line" | jq -r '.item.summary // .item.text // empty' 2>/dev/null | head -c 120)
          if [ -n "$summary" ]; then
            echo "[codex] Thinking: ${summary}"
          else
            echo "[codex] Thinking..."
          fi
          ;;
        command_execution|tool_call|function_call)
          cmd=$(echo "$line" | jq -r '.item.command // .item.name // .item.tool // empty' 2>/dev/null | head -c 100)
          status=$(echo "$line" | jq -r '.item.status // empty' 2>/dev/null)
          if [ -n "$cmd" ]; then
            echo "[codex] Exec: ${cmd} ${status:+(${status})}"
          fi
          ;;
        file_read|file_change|file_edit)
          path=$(echo "$line" | jq -r '.item.path // .item.file // empty' 2>/dev/null)
          action=$(echo "$line" | jq -r '.item.action // .item.type // empty' 2>/dev/null)
          if [ -n "$path" ]; then
            echo "[codex] File: ${action} ${path}"
          fi
          ;;
        web_search)
          query=$(echo "$line" | jq -r '.item.query // empty' 2>/dev/null | head -c 80)
          echo "[codex] Search: ${query}"
          ;;
        mcp_tool_call)
          tool=$(echo "$line" | jq -r '.item.name // empty' 2>/dev/null)
          echo "[codex] MCP: ${tool}"
          ;;
        *)
          # Show unknown item types for debugging
          echo "[codex] ${item_type}"
          ;;
      esac
      ;;
    turn.failed)
      error=$(echo "$line" | jq -r '.error.message // .error // "unknown error"' 2>/dev/null)
      echo "[codex] ERROR: ${error}"
      ;;
    # Skip noisy events: item.delta, response.*, etc.
  esac
done
