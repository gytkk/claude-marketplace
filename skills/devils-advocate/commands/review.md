---
description: >-
  Anti-sycophantic multi-pass code review. Three sequential passes focused on
  architecture fitness, future maintainability, and hidden assumptions. Enforces
  minimum findings per pass — cannot say "looks good".
argument-hint: "[files or description] [--base <branch>] [--quick]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Agent
---

# Devil's Advocate Review

Multi-pass structured code review with enforced anti-sycophancy.
Uses Claude-native tools only (no external MCP dependencies).

## Invocation

```text
/devils-advocate:review [files or description] [--base main] [--quick]
```

## Execution Steps

Execute the steps below in order. If an error occurs at any step, report it
to the user and stop.

### User Visibility Rules

| Step | Visibility | What to Show                                         |
| ---- | ---------- | ---------------------------------------------------- |
| 1    | Brief      | One-line summary of review target and mode            |
| 2    | Silent     | Internal — session setup                              |
| 3    | Brief      | Standards discovered (one-line count)                  |
| 4    | Full/Abort | Context Gate result — proceed or CONTEXT INSUFFICIENT  |
| 5    | Brief      | One-line notification per pass starting                |
| 6    | Full       | Per-pass results as they complete                      |
| 7    | Full       | Final aggregated report with verdict + unverified      |

### Step 1: Determine Review Target and Mode

Parse the user's argument for flags and review target.

**Flags:**

- `--base <branch>`: Compare `HEAD` against a base branch (e.g., `git diff main...HEAD`)
- `--quick`: Run only Pass 1 (Architecture) with minimum 1 finding

**Determine review target** (do NOT read file content yet — that happens in each pass):

#### Mode A: Explicit Target

If the user provides file paths or a description:

- File paths → Record as `TARGET_PATHS`
- Description → Record as `TARGET_DESC`

#### Mode B: Git Diff (Default)

If no explicit target, detect the diff to review. Run stat commands only:

```bash
git diff --staged --stat 2>/dev/null
git diff --stat 2>/dev/null
git diff HEAD~1 HEAD --stat 2>/dev/null
```

Use the first non-empty result. Record:

- `DIFF_COMMAND`: the command to get the full diff (e.g., `git diff --staged`)
- `DIFF_STAT`: the stat output (file list and line counts)

If `--base` is provided, use `git diff <base>...HEAD --stat` instead.

#### Mode C: Conversation Context Fallback

If neither Mode A nor B yields content, infer the most recent work from
conversation context. If not possible, ask the user and stop.

**User output**: One-line summary.
Examples: `"Reviewing: staged changes (42 lines across 3 files) — full mode"` or
`"Reviewing: src/auth/ (--quick mode)"`

### Step 2: Generate Session ID

```bash
SESSION_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.ai
```

Remember the `SESSION_ID` for all subsequent file paths.

### Step 3: Standards Discovery

Before reviewing, discover the project's established conventions and patterns.
This provides the baseline against which all passes evaluate the code.

Execute the following discovery steps using `Read`, `Grep`, `Glob`, and `Bash`:

**3a. Read documented conventions**

```bash
# Check for project-level conventions
cat CLAUDE.md 2>/dev/null
cat AGENTS.md 2>/dev/null
cat CONTRIBUTING.md 2>/dev/null
```

Record any coding standards, architectural rules, or conventions found.

**3b. Find Architecture Decision Records (ADRs)**

```bash
# Search standard ADR locations
find . -maxdepth 3 -type f \( -path "*/adr/*" -o -path "*/ADR/*" -o -path "*/decisions/*" -o -path "*/architecture/*" \) -name "*.md" 2>/dev/null | head -20
```

Record active ADR titles and key decisions.

**3c. Identify dominant patterns**

For files touched by the review target, examine sibling files and the
surrounding module to detect established patterns:

```bash
# For each changed file's directory, count recurring patterns
# e.g., if 5+ files in the same directory use a specific structure, that IS the standard
```

Use `Grep` and `Glob` to check:
- Import ordering conventions
- Error handling patterns (e.g., Result types, try/catch style, error boundaries)
- Naming conventions in the touched modules
- File structure patterns (barrel exports, index files, module layout)

**Dominant pattern rule**: If 5+ instances in the codebase follow the same
convention, that is the established pattern — even if undocumented. Deviations
are findings in Pass 1.

**3d. Detect architectural boundaries**

Identify the layer/domain the changed code belongs to:
- API/handler layer, service/business logic, data access, infrastructure?
- Are there barrel exports, API clients, repository patterns, or service layers?

Record as `DISCOVERED_STANDARDS` for use in all subsequent passes.

**User output**: One-line summary.
Example: `"Standards: 3 conventions from CLAUDE.md, 2 ADRs, dominant pattern: Result<T> error handling"`

### Step 4: Context Gate

Before proceeding with review passes, verify that sufficient context has been
gathered for a meaningful review. This prevents low-confidence reviews that
waste time with vague or unfounded findings.

**Check ALL of the following conditions:**

1. **Review target exists**: `DIFF_COMMAND` or `TARGET_PATHS` is set and non-empty
2. **Files are readable**: At least one target file or diff output is accessible
3. **Standards baseline exists**: `DISCOVERED_STANDARDS` has at least one entry
   (from CLAUDE.md, ADRs, or dominant patterns)
4. **Scope is bounded**: The review target is specific enough to evaluate
   (not "review the whole project")

**If ANY condition fails**, output a `CONTEXT INSUFFICIENT` block and stop:

```text
## CONTEXT INSUFFICIENT

Cannot produce a meaningful review. Missing:
- [ ] {list each failed condition}

Action required:
- {specific remediation for each failure}
```

Do NOT proceed with review passes when context is insufficient. A refused
review is better than a low-confidence review with unfounded findings.

**If all conditions pass**, proceed to Step 5.

**User output**: `"Context gate: passed — proceeding with review"` or the
CONTEXT INSUFFICIENT block (then stop).

### Step 5: Execute Review Passes

Set `REVIEW_MODE` to `"quick"` if `--quick` was provided, otherwise `"full"`.

Define the pass configuration:

| Pass | Name              | Focus                                                  | Min Findings | Quick |
| ---- | ----------------- | ------------------------------------------------------ | ------------ | ----- |
| 1    | architecture      | Pattern consistency, dependency direction, abstraction  | 2 (1 if quick) | Yes |
| 2    | maintainability   | Tech debt, coupling/cohesion, extensibility, assumptions | 2           | No  |
| 3    | edge_cases        | Implicit contracts, unhandled errors, concurrency       | 1 (critical) | No  |

Execute passes **sequentially**. Each pass receives the findings from all
prior passes to avoid duplicates and build on prior analysis.

#### For each pass (N = 1, 2, 3):

**5a. Compose the Agent prompt**

Build the Agent prompt with these components:

1. **Review target reference** — the diff command or file paths (NOT content).
   The Agent will use `Read`, `Bash`, `Grep`, and `Glob` to access content.

2. **Discovered standards** — include `DISCOVERED_STANDARDS` from Step 3 so the
   Agent knows the project's conventions, dominant patterns, and architectural
   boundaries. This replaces vague "follow existing patterns" with concrete evidence.

3. **Agent persona** — embed the following verbatim:

```text
Senior staff engineer. Thorough, uncompromising, respectful.
Principles: 1) Guilty until proven innocent — every change justifies its existence. 2) Evidence-based — every finding cites file:line. 3) Anti-sycophancy — FORBIDDEN from praise language (no "looks good", "LGTM", "clean", "nice", "solid", "elegant"). 4) Broader context — review against codebase, not just diff. 5) Future maintainer — think about the developer maintaining this in a year.
Anti-patterns: god objects, shotgun surgery, feature envy, primitive obsession, speculative generality, silent failures, temporal coupling.
Mindset: every line is a liability, every abstraction has a cost, make the cost visible.
```

4. **Pass-specific instructions** — from the rubrics below:

**Pass 1 (architecture):**

```text
## Pass 1: Architecture & Design Fitness

You MUST read the changed files AND their surrounding context (imports, callers, module structure) before reviewing.

## Discovered Project Standards
{DISCOVERED_STANDARDS}

Use these standards as the baseline. If the code violates a discovered standard
(documented convention, ADR decision, or dominant pattern with 5+ instances),
that is a finding — even if the code is "correct" in isolation.

Evaluate:
- Does this change fit the existing architecture or fight against it?
- Are dependency directions correct (dependencies flow inward)?
- Is the abstraction level appropriate (not over-engineered, not copy-paste)?
- Does it follow patterns established in THIS codebase (see discovered standards)?
- Are module boundaries respected?
- Are public API contracts preserved?

MINIMUM FINDINGS: {MIN_FINDINGS}. If you find fewer, you are being too lenient — re-examine the code.
```

**Pass 2 (maintainability):**

```text
## Pass 2: Future Maintainability & Tech Debt

Previous findings (do NOT duplicate these):
{PREVIOUS_FINDINGS_JSON}

Evaluate:
- Will a new team member understand this code in 6 months?
- What breaks if requirements change? How many files must change together?
- Can this be extended without modifying existing code?
- What implicit assumptions must remain true?
- Are there hardcoded values that should be parameterized?
- Do error messages help debugging?

MINIMUM FINDINGS: 2. If you find fewer, you are being too lenient — re-examine the code.
```

**Pass 3 (edge_cases):**

```text
## Pass 3: Hidden Assumptions & Edge Cases

Previous findings (do NOT duplicate these):
{PREVIOUS_FINDINGS_JSON}

Evaluate:
- What must callers/callees guarantee that is not enforced in code?
- What errors are unhandled? What happens on partial failure?
- Race conditions, deadlocks, ordering assumptions under parallel execution?
- What inputs are assumed valid but not validated?
- What if a network call, file operation, or DB query fails?
- Resource leaks: files, connections, locks, transactions?
- Boundary conditions: off-by-one, empty collections, null, max-size?

MINIMUM FINDINGS: 1 (must include at least 1 with severity "critical").
```

5. **Output format instructions:**

```text
CONCISENESS: All output MUST be strict JSON (no fences, no commentary).
- description: ≤80 chars
- suggestion: ≤80 chars
- what_could_go_wrong: ≤200 chars
- unverified items: ≤80 chars each
- Max 5 findings per pass.

Output schema:
{"name":"architecture|maintainability|edge_cases","findings":[{"severity":"critical|major|minor|info","file":"path:line","description":"...","suggestion":"..."}],"what_could_go_wrong":"...","unverified":["what you did NOT check — at least 1 item"],"confidence":1-10}

IMPORTANT: The "unverified" array MUST contain at least 1 item. List what you
could not verify in this pass (e.g., "runtime performance under load",
"behavior with concurrent writes", "compatibility with older API versions").
If you claim you verified everything, you are lying.
```

**5b. Invoke the Agent**

Spawn an Agent subagent with:

- `prompt`: The composed prompt from 3a (review target + persona + pass instructions + output format)
- `subagent_type`: `general-purpose`
- `description`: `"DA review pass {N}: {pass_name}"`
- `model`: `opus`

The Agent will:

1. Read the changed files using `Read` and `Bash` (git diff)
2. Explore surrounding context using `Grep` and `Glob`
3. Evaluate against the pass-specific criteria
4. Return strict JSON matching the per-pass schema

**5c. Validate the Agent response**

Parse the JSON from the Agent's response. Validate:

- JSON is well-formed
- `findings` array exists and has items
- Each finding has all required fields (`severity`, `file`, `description`, `suggestion`)
- `what_could_go_wrong` is present
- `unverified` array exists and has at least 1 item
- Minimum findings threshold is met:
  - Pass 1: ≥ `{MIN_FINDINGS}` findings
  - Pass 2: ≥ 2 findings
  - Pass 3: ≥ 1 finding with `severity == "critical"`

**5d. Enforce minimum findings (retry once)**

If the minimum is not met, re-invoke the Agent ONE time with this amended prompt:

```text
You returned {ACTUAL_COUNT} findings but the minimum is {REQUIRED_COUNT}.
Your previous findings: {PREVIOUS_FINDINGS}
Re-examine the code more critically. Focus on areas you may have overlooked:
- Look deeper into the module's interaction with its dependencies
- Consider what assumptions are baked into the current implementation
- Think about what breaks if the surrounding code changes
Return the COMPLETE pass result (not just new findings).
```

If the retry still does not meet the minimum, accept the result as-is and note the
shortfall in the final report.

**5e. Collect the pass result**

Store the validated per-pass JSON. Append findings to `PREVIOUS_FINDINGS` for
the next pass.

**User output**: One-line per pass completion.
Example: `"Pass 1 (Architecture): 3 findings (1 major, 2 minor) — confidence 7/10"`

### Step 6: Aggregate Results

After all passes complete, build the final result:

**6a. Merge findings**

- Collect all per-pass results into the `passes` array
- Extract `top_concerns`: up to 5 items, prioritized by severity (critical > major > minor > info), each ≤120 chars
- Build `improvements`: deduplicated suggestions from all findings, ordered by impact (high > medium > low), each ≤80 chars

**6b. Compute verdict**

Default verdict is `needs_work`. Override only if:

- **`approve`**: ALL of these must be true:
  - All findings have severity ≤ `minor`
  - Average confidence across passes ≥ 8
  - No pass failed its minimum findings threshold (indicating thoroughness)
- **`reject`**: ANY of these is true:
  - Any finding with `severity == "critical"` and the pass confidence ≥ 7
  - Multiple `major` findings indicating a fundamental design issue

**6c. Compute confidence**

Average of all per-pass confidence scores, rounded to nearest integer.
Reduce by 1 for each `critical` finding (minimum 1).

**6d. Generate summary**

One sentence, ≤100 characters, stating the verdict reason.
Example: `"3 arch violations and 1 critical race condition; needs redesign"`

### Step 7: Save and Report

**7a. Save result**

Save the final aggregated JSON to `~/.ai/review-{SESSION_ID}-result.json`:

```bash
cat > ~/.ai/review-${SESSION_ID}-result.json << 'RESULT_EOF'
{FINAL_RESULT_JSON}
RESULT_EOF
```

**7b. Present to user**

Format the report with these sections (omit empty sections):

```text
## Devil's Advocate Review

**Verdict**: {verdict} ({confidence}/10)
**Summary**: {summary}
**Mode**: {mode} | **Passes**: {pass_count}

### Top Concerns
1. [severity] file:line — description
2. ...

### Pass Results

#### Pass 1: Architecture & Design
- [severity] `file:line` — description → suggestion
- ...
> What could go wrong: {what_could_go_wrong}

#### Pass 2: Maintainability
(same format)

#### Pass 3: Edge Cases
(same format)

### Suggested Improvements (by impact)
1. [high] description
2. [medium] description
3. ...

### Not Verified
Collected from all passes. These areas were outside the scope of this review
or could not be verified through static analysis alone.
- {unverified item from pass 1}
- {unverified item from pass 2}
- {unverified item from pass 3}
- ...

💾 Full result: ~/.ai/review-{SESSION_ID}-result.json
```

**7c. Follow-up actions**

Based on verdict:

- `reject`: Propose a remediation plan for critical issues. Ask user before proceeding.
- `needs_work`: List the major/critical issues as actionable items. Ask if the user wants to address them.
- `approve`: Report the result. Note that approval with the devil's advocate process indicates genuine robustness.

## Configuration

| Variable             | Default | Description                                    |
| -------------------- | ------- | ---------------------------------------------- |
| `DA_QUICK_MIN`       | 1       | Minimum findings for quick mode (Pass 1 only)  |
| `DA_FULL_MIN_P1`     | 2       | Minimum findings for Pass 1 in full mode       |
| `DA_FULL_MIN_P2`     | 2       | Minimum findings for Pass 2                    |
| `DA_FULL_MIN_P3`     | 1       | Minimum findings for Pass 3 (must be critical) |

## Notes

- All analysis uses Claude-native tools (`Read`, `Grep`, `Glob`, `Bash`, `Agent`). No external MCP dependencies.
- Passes run sequentially so each builds on prior findings, avoiding duplicates.
- Results are saved to `~/.ai/review-{SESSION_ID}-result.json`.
- The anti-sycophancy mechanisms (minimum findings, banned phrases, default-deny verdict) are intentionally aggressive. If a review passes all three passes with an `approve` verdict, the code has genuinely earned it.
