# codex-debate

Structured multi-round debate between **Claude** (builder/proposer) and **Codex**
(skeptical reviewer/challenger) for Claude Code. Produces actionable decisions with
rationale, risks, and next steps.

## Quick Start

```bash
# 1. Prerequisites
npm install -g @openai/codex
codex login

# 2. Register Codex MCP server (if not already done)
claude mcp add -s user codex -- codex mcp-server

# 3. Install plugin (option A: marketplace — if published)
claude plugin add gytkk/codex-debate

# 3. Install plugin (option B: local)
claude plugin add --local /path/to/skills/codex-debate

# 4. Use it
/codex-debate:debate "Should we migrate from REST to GraphQL?"
```

## Usage

```text
/codex-debate:debate "topic" [--rounds 3]
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `"topic"` | *(required)* | The debate subject |
| `--rounds N` | `3` | Number of debate rounds (auto-adjusted to odd) |

Context is gathered automatically based on the topic — git diff, project structure, and
relevant files are detected without explicit flags.

### Examples

```bash
# Debate with default settings
/codex-debate:debate "Should we split the monolith into microservices?"

# Architecture review — auto-detects project structure
/codex-debate:debate "Auth module design review"

# Debate with more rounds
/codex-debate:debate "Database query optimization strategy" --rounds 5
```

### Alternative: Global Command

For `/codex-debate "topic"` invocation (without `:debate` suffix), create a global command wrapper:

```bash
mkdir -p ~/.claude/commands
cat > ~/.claude/commands/codex-debate.md << 'EOF'
---
description: "Structured debate between Claude and Codex"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

Execute the /codex-debate:debate skill with the provided arguments.
Pass all arguments through exactly as given.
EOF
```

## How It Works

### Debate Flow

```
R0 (Claude)  ─── Initial proposal with position, approach, trade-offs
       │
R1 (Codex)   ─── Challenge: critique, risks, alternatives, score
       │
R2 (Claude)  ─── Revision: accepted critiques, rebuttals, updated approach
       │
R3 (Codex)   ─── Final verdict: APPROVE / REJECT / CONDITIONAL / RECOMMEND / INCONCLUSIVE
       │
    Output    ─── Summary + transcript saved to .claude/debates/
```

- **Even rounds** (0, 2, 4…): Claude reasons and proposes
- **Odd rounds** (1, 3, 5…): Codex challenges via MCP tools
- Last round is always Codex (verdict)

### Roles

| Agent | Role | Behavior |
|-------|------|----------|
| **Claude** | Builder | Proposes, defends, revises based on valid critique |
| **Codex** | Reviewer | Challenges, identifies risks, proposes alternatives |

### Evaluation

Proposals are evaluated holistically across: correctness, architecture, security,
performance, testing, maintainability, feasibility, and risk. Dimensions are weighted
based on the specific topic and context. See [`references/rubrics.md`](references/rubrics.md).

## Output

### Console Summary

```markdown
# Debate Result: {topic}
Outcome: APPROVE | Confidence: 8/10

## Conclusion
## Rationale (3-7 bullets)
## Risks & Mitigations (table)
## Next Actions (checklist)
## Unresolved Questions
```

### Artifact File

Saved to `.claude/debates/YYYYMMDD-HHMM-slug.md` with:
- YAML frontmatter (topic, rounds, date, outcome, confidence)
- Full summary
- Complete transcript (all rounds)
- Raw verdict JSON

## Architecture

```
skills/codex-debate/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── commands/
│   └── debate.md                # Main command (skill instructions)
├── agents/
│   └── codex-debate-agents.md   # Codex reviewer persona
├── references/
│   ├── debate-schema.json       # Final verdict JSON schema
│   └── rubrics.md               # Evaluation criteria
├── tests/
│   ├── lib.sh                   # Extracted functions for testing
│   ├── test-mask-secrets.sh     # Secret masking unit tests
│   ├── test-parse-args.sh       # Argument parsing unit tests
│   ├── test-save-debate.sh      # Save/slug unit tests
│   └── test-collect-context.sh  # Context collection unit tests
└── README.md
```

### Design Decisions

1. **Claude Code Plugin** (not external script): Native integration with Claude Code's
   permission system, tool allowlists, and plugin distribution
2. **Markdown command** (not code): Follows the established codex plugin pattern where
   the command `.md` file IS the implementation — Claude follows the instructions
3. **Shell-based utilities**: No Node/Python runtime dependency; works in any environment
   with bash and git
4. **MCP thread-based Codex**: Uses `mcp__codex__codex` + `mcp__codex__codex-reply` for
   Codex conversation continuity across rounds
5. **Project-scoped storage**: `.claude/debates/` per project prevents cross-contamination

## Security

- **Command allowlist**: Only `git diff`, `git log`, `date`, `mkdir`, `ls`, `rm` (tmp only),
  `head`, `wc`, `sed` (masking only)
- **Secret masking**: AWS keys, GitHub tokens, OpenAI keys, generic `password=`/`token=`
  patterns, long base64 strings — all masked before inclusion
- **No auto-execution**: Files in context are referenced by path, not executed
- **Read-only Codex sandbox**: Codex MCP runs with `sandbox: "read-only"`
- **Smart context detection**: Context auto-gathered based on topic analysis

## Testing

Run all tests:

```bash
bash skills/codex-debate/tests/test-mask-secrets.sh
bash skills/codex-debate/tests/test-parse-args.sh
bash skills/codex-debate/tests/test-save-debate.sh
bash skills/codex-debate/tests/test-collect-context.sh
```

### Integration Testing Guide

For full end-to-end testing with actual Codex model calls:

1. Ensure `codex` CLI is installed and authenticated
2. Have a project with git history (for auto-detected context)
3. Run: `/codex-debate:debate "Test: should we add caching?" --rounds 1`
4. Verify:
   - Round 0 (Claude) produces structured proposal
   - Round 1 (Codex) produces structured critique via MCP
   - Summary is displayed with outcome
   - Artifact saved to `.claude/debates/`

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBATE_ROUNDS` | `3` | Default debate rounds |
| `DEBATE_CONTEXT_MAX_CHARS` | `2000` | Max context size |
| `DEBATE_MAX_RESPONSE_WORDS` | `500` | Per-round word limit (Codex) |

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
- Codex authentication (`codex login`)
- Codex MCP server registered (`claude mcp add -s user codex -- codex mcp-server`)
- Claude Code with plugin support

## Portability

This plugin is self-contained and can be used in any project:

1. **As a plugin**: Copy `skills/codex-debate/` to your marketplace or use `claude plugin add --local`
2. **As part of existing codex plugin**: Copy `commands/debate.md` and `agents/codex-debate-agents.md`
   into the existing codex plugin's directory structure
3. **As a global command**: Use the wrapper pattern from the "Alternative: Global Command" section
