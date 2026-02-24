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

**Truncation**: If content exceeds `CRITIC_MAX_DIFF_LINES` (default: 500),
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

#### 4b. Compose Prompt

Substitute `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}`, and `{AGENT_PERSONA}` in the template below to compose the prompt string.

**When `CONTENT_TYPE` is `"diff"`**, compose `{CONTENT_SECTION}` as:

````text
## Code Changes (Diff)
```diff
{REVIEW_CONTENT}
```
````

**When `CONTENT_TYPE` is `"arbitrary"`**, compose `{CONTENT_SECTION}` as:

````text
## Content Under Review
```
{REVIEW_CONTENT}
```
````

**Initial analysis prompt template**:

```text
{AGENT_PERSONA}

---

You are a meticulous code reviewer and critic. Your task is to evaluate whether
the provided content correctly and completely fulfills the original user request.

## Original User Request
{USER_REQUEST}

{CONTENT_SECTION}

## Instructions
1. Analyze the content against the original request.
2. Check for: correctness, completeness, security, style consistency, edge cases, and potential bugs.
3. For code diffs, also check: error handling, performance, and testing coverage.
4. For plans or designs, check: feasibility, completeness, potential risks, and missing considerations.
5. Produce a structured JSON review.

## Output Requirements
Respond with ONLY valid JSON matching this structure:
{
  "verdict": "pass" | "warn" | "fail",
  "score": <0-10>,
  "summary": "<one paragraph summary>",
  "issues": [
    {
      "severity": "critical" | "major" | "minor" | "info",
      "category": "<category>",
      "file": "<file path if applicable>",
      "line": <line number if applicable>,
      "description": "<what the issue is>",
      "suggestion": "<how to fix>"
    }
  ],
  "checklist": [
    {
      "item": "<what was checked>",
      "passed": true | false,
      "note": "<additional context>"
    }
  ],
  "iteration": {ITERATION}
}

Be thorough but fair. Only flag real issues, not stylistic preferences unless they violate project conventions.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4c. Codex MCP Invocation

Call the `mcp__codex__codex` tool, passing the composed prompt as the `prompt` parameter.

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
Review your prior analysis (iteration {PREV_ITERATION}) and refine it.

## Refinement Instructions
1. Re-examine each issue: remove false positives, add missed problems.
2. Recalibrate the score based on your refined understanding.
3. Ensure the checklist is comprehensive.
4. If your previous analysis was already thorough and accurate, you may keep
   it largely unchanged but update the iteration number.

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
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
| `CRITIC_MAX_DIFF_LINES` | 500     | Maximum diff lines       |

## Notes

- Analysis is performed via Codex MCP tools, with thread-based conversations enabling iterative refinement.
- Results are saved to `~/.ai/critic-{SESSION_ID}-result.json`.
- Runtime outputs are stored in the `~/.ai/` directory (does not pollute the project directory).
