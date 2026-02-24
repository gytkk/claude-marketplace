---
description: >-
  Verification and feedback for code, plans, and arbitrary content powered
  by Codex. Independently validates whether code changes, plans, or any
  text fulfill the original request.
argument-hint: "<original user request or description of content to verify>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Critic

Uses Codex MCP tools to independently verify whether code changes (diffs),
plans, or arbitrary content fulfill the original user request, providing
structured feedback.

## Invocation

```text
/codex:critic <original user request or description of content to verify>
```

## Execution Steps

Execute the steps below in order. If an error occurs at any step, report it to the user and stop.

### User Visibility Rules

Most steps are internal and should NOT produce user-facing output. Only the following should be shown to the user:

| Step | Visibility | What to Show |
|------|-----------|--------------|
| 1    | Error only | Show only if codex CLI is not installed |
| 2    | Brief     | One-line summary of determined input (e.g., "Reviewing: staged changes (42 lines)") |
| 3    | Brief     | One-line notification that review is starting (e.g., "Running Codex Critic...") |
| 4–6  | Silent    | Do not show anything to the user |
| 7    | Full      | Final result report with follow-up actions |

### Step 1: Prerequisites Check

Verify that the codex CLI is installed via Bash. If it fails, report the error message to the user and stop.

```bash
command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"; exit 1; }
```

**Authentication**: Pre-authentication via `codex login` is required. Authentication failures are reported by the MCP tool itself.

**User output**: None on success. On failure, show install instructions and stop.

### Step 2: Determine Input

Determine the content to verify based on the following priority.

#### Mode A: Explicit Content (Arbitrary Input)

If the user provides any of the following, use that content as `REVIEW_CONTENT`:

- Specified file path → Read with the Read tool
- Directly passed text block → Use as-is
- Implementation plan or design document → Collect that content

Set `CONTENT_TYPE` to `"arbitrary"`.

#### Mode B: Git Diff (Default Mode)

If no explicit content is provided, collect git diff. Cascade in the following order, using the first non-empty result:

```bash
# 1. Staged changes
git diff --staged 2>/dev/null

# 2. Working tree changes
git diff 2>/dev/null

# 3. Last commit
git diff HEAD~1 HEAD 2>/dev/null
```

If a diff exists, set `CONTENT_TYPE` to `"diff"`.

**Truncation**: If content exceeds `CRITIC_MAX_DIFF_LINES` (default: 300),
use only the first N lines and append `[... truncated ...]`.

#### Mode C: Conversation Context Fallback

If neither Mode A nor B yields content, infer the most recent work
(code changes, plans, etc.) from the current conversation context.
If inference is not possible, ask the user to specify the verification target and stop.

**User output**: One-line summary of the determined input (e.g., "Reviewing: staged changes (42 lines)" or "Reviewing: `auth-plan.md`").

### Step 3: Generate Session ID and Prepare Output Directory

Generate a unique session ID and use it for all subsequent output filenames.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

Remember the `SESSION_ID` value for use in all subsequent file paths.

**User output**: One-line notification (e.g., "Running Codex Critic...").

### Step 4: Initial Analysis (Iteration 1)

#### 4a. Read Agent Persona

Use the Read tool to read `${CLAUDE_PLUGIN_ROOT}/agents/codex-critic-agents.md` and capture the `AGENT_PERSONA` content.

#### 4b. Compose Prompt Parameters

Compose three separate parameters to keep the MCP tool call concise in the UI.

**`developer-instructions`**: Set to the `{AGENT_PERSONA}` content read in Step 4a.

**`base-instructions`**: Use the following static template (substitute `{ITERATION}` only):

```text
Meticulous code reviewer. Evaluate whether content fulfills the original request.
Check: correctness, completeness, security, style, edge cases, bugs. For diffs: error handling, performance, tests. For plans: feasibility, risks.
CONCISENESS: summary ≤100 chars. Max 5 issues (no checklist/category). description ≤80, suggestion ≤80 chars.
JSON only, no fences: {"verdict":"pass|warn|fail","score":0-10,"summary":"...","issues":[{"severity":"critical|major|minor|info","file":"file:line","description":"...","suggestion":"..."}],"iteration":{ITERATION}}
Only flag real issues.
```

**`prompt`**: Compose from `{USER_REQUEST}` and `{CONTENT_SECTION}` only.

When `CONTENT_TYPE` is `"diff"`, compose `{CONTENT_SECTION}` as:

````text
## Code Changes (Diff)
```diff
{REVIEW_CONTENT}
```
````

When `CONTENT_TYPE` is `"arbitrary"`, compose `{CONTENT_SECTION}` as:

````text
## Content Under Review
```
{REVIEW_CONTENT}
```
````

The prompt string:

```text
## Original User Request
{USER_REQUEST}

{CONTENT_SECTION}
```

#### 4c. Codex MCP Invocation

Call the `mcp__codex__codex` tool with three parameters:
- `prompt`: The task-specific prompt composed above (user request + content only)
- `developer-instructions`: The agent persona from Step 4a
- `base-instructions`: The static instructions and output schema from Step 4b

Save the `threadId` from the response and parse the JSON result from the response text.

#### 4d. Result Validation

Verify that the JSON is valid. If invalid, report the error and stop.

Examine the `verdict` and `score` values.

### Step 5: Iterative Refinement Loop

**Stop conditions**: If any of the following are met, stop iterating and proceed to Step 6:

- `verdict == "pass"`
- `score >= 8`
- Iteration count has reached `CRITIC_MAX_ITER` (default: 5)

**Continue condition**: If stop conditions are not met, request refinement via `mcp__codex__codex-reply`.

#### Refinement Message Template

Pass the `threadId` and the message below to the `mcp__codex__codex-reply` tool.
Since Codex retains previous context, there is no need to resend the original content.

```text
Refine iteration {PREV_ITERATION}: remove false positives, add missed issues, recalibrate score. Stay concise (summary ≤100 chars, descriptions ≤80 chars, max 5 issues, no checklist).
JSON only, same schema, iteration={ITERATION}.
```

Parse the JSON result from the response text and re-check `verdict` and `score`.

**Error fallback**: If the MCP call fails, use the previous iteration's result as the final result.

### Step 6: Save Final Result

Save the final JSON result to `~/.ai/critic-{SESSION_ID}-result.json`:

```bash
cat > ~/.ai/critic-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
```

### Step 7: Report Results and Follow-up

Present the result to the user concisely. Only show sections with meaningful data — omit empty tables or sections.

Focus on: verdict, score, summary, and critical/major issues with suggestions.
Minor or info-level issues should be mentioned as a count only (e.g., "2 minor issues omitted").
Checklist items should only be shown if any failed.

**Follow-up actions** (include inline at the end of the report):

- `verdict` is `fail`: Propose a fix plan for each issue.
- `verdict` is `warn`: Suggest whether to fix the major issues to the user.
- `verdict` is `pass`: Report the result and finish.

Proceed with fixes only after user approval.

## Configuration

| Environment Variable    | Default | Description              |
| ----------------------- | ------- | ------------------------ |
| `CRITIC_MAX_ITER`       | 5       | Maximum iteration count  |
| `CRITIC_MAX_DIFF_LINES` | 300     | Maximum diff lines       |

## Notes

- Analysis is performed via Codex MCP tools, with thread-based conversations enabling iterative refinement.
- Results are saved to `~/.ai/critic-{SESSION_ID}-result.json`.
- Runtime outputs are stored in the `~/.ai/` directory (does not pollute the project directory).
