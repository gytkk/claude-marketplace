---
description: >-
  Deep analysis powered by Codex. Analyzes code, logs, errors, performance,
  and any target to provide structured insights.
argument-hint: "<description of analysis target>"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
  - WebSearch
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Codex Analyze

Performs deep analysis of code, logs, errors, performance, and any target using
Codex MCP tools, delivering structured and actionable insights.

## Invocation

```text
/codex:analyze <description of analysis target>
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

### Step 2: Determine Input

Determine the analysis target through the following 3-step cascade.

#### Mode A: Explicit Content

If the user explicitly provides file paths, directories, or text blocks, collect that content as `ANALYSIS_CONTENT`.

- File path: Read the content using the Read tool
- Directory: Collect file list with Glob, then Read key files
- Text block: Use as-is

Set `CONTENT_TYPE` to `"explicit"`.

#### Mode B: Project Structure (Default Mode)

If no explicit content is provided, collect the project structure as `ANALYSIS_CONTENT`.

Items to collect:
- File structure (via equivalent commands like `find`, `ls`, etc.)
- Key file contents (README, config files, entry points)
- Key module samples needed to understand the analysis target

Set `CONTENT_TYPE` to `"project"`.

#### Mode C: Conversation Context Fallback

If neither Mode A nor B yields sufficient input, infer the analysis target from the current conversation context.
If inference is not possible, ask the user to specify the analysis target and stop.

**Truncation**: If content exceeds `ANALYZE_MAX_CONTENT_LINES` (default: 1000),
use only the first N lines and append `[... truncated ...]`.

### Step 3: Generate Session ID and Prepare Output Directory

Generate a unique session ID and use it for all subsequent output filenames.

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
echo "Session ID: $SESSION_ID"
```

Remember the `SESSION_ID` value for use in all subsequent file paths.

### Step 4: Initial Analysis (Iteration 1)

#### 4a. Read Agent Persona

Use the Read tool to read `${CLAUDE_PLUGIN_ROOT}/agents/codex-analyze-agents.md` and capture the `AGENT_PERSONA` content.

#### 4b. Compose Prompt

Substitute `{USER_REQUEST}`, `{CONTENT_SECTION}`, `{ITERATION}`, and `{AGENT_PERSONA}` in the template below to compose the prompt string.

**When `CONTENT_TYPE` is `"explicit"`**, compose `{CONTENT_SECTION}` as:

````text
## Analysis Target
```
{ANALYSIS_CONTENT}
```
````

**When `CONTENT_TYPE` is `"project"`**, compose `{CONTENT_SECTION}` as:

````text
## Project Structure
```
{ANALYSIS_CONTENT}
```
````

**Initial analysis prompt template**:

```text
{AGENT_PERSONA}

---

You are a systematic, evidence-based analyst. Your task is to perform a deep
analysis of the provided content and produce structured, actionable insights.

## Analysis Request
{USER_REQUEST}

{CONTENT_SECTION}

## Instructions
1. Thoroughly examine the provided content.
2. Identify patterns, issues, and opportunities across all relevant dimensions.
3. For code: check architecture, patterns, complexity, dependencies, quality, security, performance.
4. For logs: check patterns, anomalies, error frequency, correlations.
5. For any content: identify root causes, not just symptoms.
6. Quantify findings where possible (counts, percentages, complexity scores).
7. Prioritize findings by severity and impact.
8. Provide actionable, specific recommendations with estimated effort.

## Output Requirements
Respond with ONLY valid JSON matching this structure:
{
  "status": "complete" | "partial",
  "summary": "<one paragraph summary of analysis>",
  "scope": "<what was analyzed>",
  "findings": [
    {
      "category": "<e.g., architecture, security, performance, quality, dependency, pattern>",
      "severity": "critical" | "major" | "minor" | "info",
      "title": "<short title>",
      "description": "<detailed description>",
      "evidence": "<file:line reference or data evidence>",
      "recommendation": "<specific actionable recommendation>"
    }
  ],
  "metrics": {
    "<metric_name>": <value>,
    ...
  },
  "recommendations": [
    {
      "priority": "high" | "medium" | "low",
      "title": "<short title>",
      "description": "<detailed description with expected impact>",
      "effort": "trivial" | "small" | "medium" | "large"
    }
  ],
  "iteration": {ITERATION}
}

Be thorough and evidence-based. Every finding must reference specific files, lines, or data.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

#### 4c. Codex MCP Invocation

Call the `mcp__codex__codex` tool, passing the composed prompt as the `prompt` parameter.

Save the `threadId` from the response and parse the JSON result from the response text.

#### 4d. Result Validation

Verify that the JSON is valid. If invalid, report the error and stop.

Examine the `status` and `findings` values.

### Step 5: Iterative Refinement Loop

**Stop conditions**: If any of the following are met, stop iterating and proceed to Step 6:

- `status == "complete"` and no critical issues in `findings`
- Iteration count has reached `ANALYZE_MAX_ITER` (default: 3)

**Continue condition**: If stop conditions are not met, request refinement via `mcp__codex__codex-reply`.

#### Refinement Message Template

Pass the `threadId` and the message below to the `mcp__codex__codex-reply` tool.
Since Codex retains previous context, there is no need to resend the original content.

```text
Continue refining your analysis from iteration {PREV_ITERATION}.

## Refinement Instructions
1. Validate previous findings: keep accurate findings, correct weak ones.
2. Search for missed patterns, correlations, and root causes.
3. Improve quantification and evidence quality.
4. Re-prioritize findings and recommendations by impact and effort.
5. If analysis is already complete, keep structure and update iteration only.

Respond with ONLY valid JSON (same schema as before).
Set "iteration" to {ITERATION}.
Output ONLY the JSON object, no markdown fences, no explanation before or after.
```

Parse the JSON result from the response text and re-check `status` and `findings`.

**Error fallback**: If the MCP call fails, use the previous iteration's result as the final result.

### Step 6: Save Final Result

Save the final JSON result to `~/.ai/analyze-{SESSION_ID}-result.json`:

```bash
cat > ~/.ai/analyze-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
```

### Step 7: Report Results

Present the JSON result to the user in a concise format. Only show sections that contain meaningful data — omit empty tables or sections.

Keep the output minimal: summary, critical/major findings, and top recommendations.
Minor or info-level findings should be mentioned as a count only (e.g., "3 minor findings omitted").

### Step 8: Suggest Follow-up Actions

- If critical issues exist: propose a prioritized action plan for immediate response.
- If recommendations exist: suggest an implementation order based on priority and effort.
- Otherwise: report analysis complete and finish.

## Configuration

| Environment Variable        | Default | Description              |
| --------------------------- | ------- | ------------------------ |
| `ANALYZE_MAX_ITER`          | 3       | Maximum iteration count  |
| `ANALYZE_MAX_CONTENT_LINES` | 1000    | Maximum content lines    |

## Notes

- Analysis is performed via Codex MCP tools, with thread-based conversations enabling iterative refinement.
- Results are saved to `~/.ai/analyze-{SESSION_ID}-result.json`.
- Runtime outputs are stored in the `~/.ai/` directory.
