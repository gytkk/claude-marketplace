---
description: >-
  Verification and feedback for code, plans, and arbitrary content powered
  by Codex. Independently validates whether code changes, plans, or any
  text fulfill the original request.
argument-hint: "<original user request or description of content to verify>"
allowed-tools:
  - Bash
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

Determine the review target. **Do NOT read file content or run git diff** — Codex will access
files and run commands directly via the `cwd` parameter.

#### Mode A: Explicit Target (Arbitrary Input)

If the user provides any of the following:

- File path → Record the path (do NOT Read the content)
- Text block → Use as-is (embed in prompt; this is the only case where content is embedded)
- Implementation plan or design document → Record its file path

Set `CONTENT_TYPE` to `"arbitrary"` and store paths in `TARGET_PATHS`.

#### Mode B: Git Diff (Default Mode)

If no explicit content is provided, determine which diff type to review.
Run the following **only to check if a diff exists** (not to capture content):

```bash
# Check existence only — do NOT capture output for embedding
git diff --staged --stat 2>/dev/null   # 1. Staged changes
git diff --stat 2>/dev/null            # 2. Working tree changes
git diff HEAD~1 HEAD --stat 2>/dev/null # 3. Last commit
```

Use the first non-empty result and record the corresponding `DIFF_COMMAND`:
- `"git diff --staged"`, `"git diff"`, or `"git diff HEAD~1 HEAD"`

Set `CONTENT_TYPE` to `"diff"`.

#### Mode C: Conversation Context Fallback

If neither Mode A nor B yields content, infer the most recent work
(code changes, plans, etc.) from the current conversation context.
If inference is not possible, ask the user to specify the verification target and stop.

**User output**: One-line summary (e.g., "Reviewing: staged changes" or "Reviewing: `auth-plan.md`").

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

#### 4a. Compose Prompt Parameters

**CRITICAL**: The `prompt` parameter MUST contain only the user request and a review target reference.
The entire `prompt` value MUST be under 500 characters. If it exceeds 500 characters, you are doing it wrong.

**`developer-instructions`**: Use the following agent persona verbatim:

```text
Skeptical, thorough code reviewer focused on finding real risks before production.
Principles: 1) Guilty until proven innocent — actively disprove correctness. 2) Evidence over intuition — anchor findings in code refs. 3) Severity discipline — separate blockers/warnings/nits. 4) Intent alignment — code missing requirements is incorrect.
Checklist: requirement match, condition logic, null/empty/boundary probing, concurrency hazards, timeout/retry, error propagation, cleanup on failure, partial-failure state, input validation, injection risks, secret leakage, auth checks, dependency safety, algorithmic hotspots, maintainability.
Anti-patterns: silent catches, untracked TODOs, commented-out code, magic numbers, type-safety bypasses, broad exceptions, missing cleanup, unsafe shared state, string-built SQL/HTML/shell.
Mindset: strict and production-oriented — better a justified false positive than a missed critical defect.
```

**`base-instructions`**: Use the following static template (substitute `{ITERATION}` only):

```text
Meticulous code reviewer. Evaluate whether content fulfills the original request.
IMPORTANT: Read the specified files or run the specified git diff command FIRST. Cite evidence from actual content. Never answer without reading.
Check: correctness, completeness, security, style, edge cases, bugs. For diffs: error handling, performance, tests. For plans: feasibility, risks.
CONCISENESS: summary ≤100 chars. Max 5 issues (no checklist/category). description ≤80, suggestion ≤80 chars.
JSON only, no fences: {"verdict":"pass|warn|fail","score":0-10,"summary":"...","issues":[{"severity":"critical|major|minor|info","file":"file:line","description":"...","suggestion":"..."}],"iteration":{ITERATION}}
Only flag real issues.
```

**`prompt`**: Compose from `{USER_REQUEST}` and review target reference only.

When `CONTENT_TYPE` is `"diff"`:

```text
## Original User Request
{USER_REQUEST}

## Review Target
Run `{DIFF_COMMAND}` to see the changes to review.
```

When `CONTENT_TYPE` is `"arbitrary"` with file paths:

```text
## Original User Request
{USER_REQUEST}

## Review Target
{TARGET_PATHS}
```

When `CONTENT_TYPE` is `"arbitrary"` with a text block, embed the text directly in the prompt.

Example of a correct prompt (under 500 chars):
> `## Original User Request\nVerify the refactored auth module.\n\n## Review Target\nRun \`git diff --staged\` to see the changes to review.`

#### 4b. Codex MCP Invocation

Call the `mcp__codex__codex` tool with the following parameters:
- `prompt`: The task-specific prompt (under 500 chars — review target reference only, NOT content)
- `developer-instructions`: The agent persona from Step 4a
- `base-instructions`: The static instructions and output schema from Step 4a
- `cwd`: Current working directory (absolute path from `$PWD`)
- `sandbox`: `"read-only"`
- `approval-policy`: `"never"`

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

## Notes

- Analysis is performed via Codex MCP tools, with thread-based conversations enabling iterative refinement.
- Results are saved to `~/.ai/critic-{SESSION_ID}-result.json`.
- Runtime outputs are stored in the `~/.ai/` directory (does not pollute the project directory).
