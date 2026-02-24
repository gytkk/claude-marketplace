---
description: >-
  Autonomous deep worker powered by Codex. Delegates complex implementation
  tasks via Codex MCP tools, autonomously performing explore, plan, execute,
  and verify.
argument-hint: "<description of task objective>"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Hephaestus

Autonomously performs complex implementation tasks using Codex MCP tools.
Like Hephaestus (the Greek god of the forge), given a goal it independently
completes exploration, planning, execution, and verification.

## Invocation

```text
/codex:hephaestus <description of task objective>
```

## Execution Steps

Execute the steps below in order. If an error occurs at any step, report it to the user and stop.

### Step 1: Prerequisites Check

Verify that the codex CLI is installed via Bash.

```bash
command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"; exit 1; }
```

If this command fails (exit 1), immediately report the installation instructions to the user and **stop skill execution**.
Do not proceed to any subsequent steps.

### Step 2: Gather Context

Collect the context needed for the task, including:

1. **User request**: The task objective passed when invoking the skill
2. **Project structure**: Relevant file/directory listings (collected via Glob/Grep)
3. **Related code**: Contents of files directly related to the task (collected via Read)
4. **Existing patterns**: Code style and structural patterns of the project

Collection criteria:
- If the user mentioned specific files, Read those files
- If the work area is clear, explore that directory with Glob
- If the work area is unclear, search for related code with Grep
- Limit context to a maximum of 300 lines (if exceeded, excerpt only key portions)

Store collected context in the `TASK_CONTEXT` variable.

### Step 3: Generate Session ID and Prepare Output Directory

Generate a unique session ID and use it for all subsequent output filenames.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

Remember the `SESSION_ID` value for use in all subsequent file paths.

### Step 4: Initial Execution (Iteration 1)

#### 4a. Read Agent Persona

Use the Read tool to read `${CLAUDE_PLUGIN_ROOT}/agents/codex-hephaestus-agents.md` and capture the `AGENT_PERSONA` content.

#### 4b. Compose Prompt

Substitute `{USER_REQUEST}`, `{TASK_CONTEXT}`, `{ITERATION}`, and `{AGENT_PERSONA}` in the template below to compose the prompt string.

**Prompt template**:

```text
{AGENT_PERSONA}

---

You are Hephaestus, an autonomous deep worker. Complete the following task
end-to-end. Do NOT ask questions. Do NOT stop early. Execute until done.

## Task
{USER_REQUEST}

## Project Context
{TASK_CONTEXT}

## Execution Rules
1. EXPLORE: Read all relevant files first. Understand existing patterns.
2. PLAN: Determine the exact changes needed (file-by-file).
3. EXECUTE: Make precise, surgical changes. Follow existing code style exactly.
4. VERIFY: Re-read every modified file. Check for syntax errors and logical mistakes.

If verification fails, return to step 1 and try a different approach (max 3 attempts).
After 3 failures, revert and report what went wrong.

## Hard Constraints
- Follow existing codebase patterns exactly
- Never suppress type errors (as any, @ts-ignore, # type: ignore)
- Never leave code in a broken state
- Never delete tests to make things pass
- Never add TODOs — complete the work now
- Never introduce commented-out code

## Output Requirements
After completing your work, respond with ONLY valid JSON matching this structure:
{
  "status": "complete" | "partial" | "failed",
  "summary": "<one paragraph of what was accomplished>",
  "approach": "<description of approach taken>",
  "files_modified": [
    {"path": "<relative path>", "action": "create|modify|delete", "description": "<what changed>"}
  ],
  "verification": {
    "syntax_check": true|false,
    "build_check": true|false,
    "test_check": true|false,
    "notes": "<verification details>"
  },
  "issues": [
    {"severity": "critical|major|minor", "description": "<issue>", "resolution": "<how resolved or why unresolved>"}
  ],
  "next_steps": ["<remaining work if any>"],
  "iteration": {ITERATION}
}

Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4c. Codex MCP Invocation

Call the `mcp__codex__codex` tool, passing the composed prompt as the `prompt` parameter.

Save the `threadId` from the response and parse the JSON result from the response text.

#### 4d. Result Validation

Verify that the JSON is valid. If invalid, report the error and stop.

Examine the `status` and `issues` values.

### Step 5: Iterative Refinement Loop

**Stop conditions**: If any of the following are met, stop iterating and proceed to Step 6:

- `status == "complete"` and no critical/major issues in `issues`
- Iteration count has reached `HEPHAESTUS_MAX_ITER` (default: 3)

**Continue condition**: If stop conditions are not met, request refinement via `mcp__codex__codex-reply`.

#### Refinement Message Template

Pass the `threadId` and the message below to the `mcp__codex__codex-reply` tool.
Since Codex retains previous context, there is no need to resend the original content.

```text
The previous iteration was incomplete or had issues. Continue the work.

## Previous Result Summary
- Status: {PREV_STATUS}
- Issues: {PREV_ISSUES_SUMMARY}

## Instructions
1. If status was "partial": complete the remaining work.
2. If status was "failed": try a different approach entirely.
3. If there were critical/major issues: fix them.
4. Verify ALL changes (both previous and new).

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

Parse the JSON result from the response text and re-check `status` and `issues`.

**Error fallback**: If the MCP call fails, use the previous iteration's result as the final result.

### Step 6: Save Final Result

Save the final JSON result to `~/.ai/hephaestus-{SESSION_ID}-result.json`:

```bash
cat > ~/.ai/hephaestus-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
```

### Step 7: Verify Changes

Claude Code independently verifies the work produced by Codex:

1. Check actual changes with `git diff`
2. Read modified files with the Read tool to review contents
3. Cross-reference `files_modified` in the JSON result against the actual git diff
4. Review for syntax errors, logical issues, and violations of existing patterns

If verification reveals problems, report them to the user.

### Step 8: Report Results

Present the result to the user concisely. Only show sections with meaningful data — omit empty tables or sections.

Focus on: status, summary, files modified (as a brief list), and any unresolved issues.
Verification details and next steps should only appear if they contain notable information.

### Step 9: Suggest Follow-up Actions

- `status` is `complete` with no issues: Show changes to the user and ask whether to commit.
- `status` is `complete` but minor issues exist: Present the issue list and suggest whether to fix them.
- `status` is `partial`: Explain incomplete portions and suggest whether Claude Code should complete them directly or re-run.
- `status` is `failed`: Analyze the failure cause and propose alternatives.

Proceed with fixes only after user approval.

## Configuration

| Environment Variable    | Default | Description            |
| ----------------------- | ------- | ---------------------- |
| `HEPHAESTUS_MAX_ITER`   | 3       | Maximum iteration count|

## Notes

- Tasks are performed via Codex MCP tools, with thread-based conversations enabling iterative refinement.
- Results are saved to `~/.ai/hephaestus-{SESSION_ID}-result.json`.
- Runtime outputs are stored in the `~/.ai/` directory (does not pollute the project directory).
- After Codex completion, Claude Code independently verifies changes (Step 7).
