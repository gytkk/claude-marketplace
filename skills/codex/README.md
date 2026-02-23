# Codex Plugin

OpenAI Codex MCP integration for Claude Code. Provides three commands via
`codex mcp-server` (MCP tool-based, thread-aware conversations).

## Commands

### `/codex:critic`

Code/plan/content review and validation via Codex MCP tools.

- Validates code changes (git diff), plans, or arbitrary content against user requirements
- Iterative refinement via thread-based conversations (up to 5 iterations by default)
- Scoring system (0-10) with verdict: pass/warn/fail
- Session-scoped output files: `~/.ai/critic-{SESSION_ID}-result.json`

### `/codex:hephaestus`

Autonomous deep worker for complex implementation tasks.

- Self-directed execution: explore → plan → execute → verify
- Iterative execution via thread-based conversations (up to 3 iterations by default)
- Self-verification of changes
- Session-scoped output files: `~/.ai/hephaestus-{SESSION_ID}-result.json`

### `/codex:analyze`

Deep analysis for code, logs, errors, performance, and arbitrary content.

- Systematic, evidence-based analysis with structured findings
- Iterative deepening via thread-based conversations (up to 3 iterations by default)
- Session-scoped output files: `~/.ai/analyze-{SESSION_ID}-result.json`

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- Codex authentication (`codex login`)
- Codex MCP server registered in Claude Code (`claude mcp add -s user codex -- codex mcp-server`)

## Architecture

Skills use `mcp__codex__codex` and `mcp__codex__codex-reply` MCP tools instead of
`codex exec` CLI. This provides:

- **No file-based I/O**: Prompts passed directly as parameters (no `/tmp/` files)
- **Thread-based conversations**: `threadId` enables iterative refinement with full context
- **Structured responses**: Direct MCP tool responses (no JSONL streaming)
- **Simplified setup**: No `CODEX_HOME` directory management or symlinks needed

## Structure

```
skills/codex/
├── .claude-plugin/plugin.json    # Plugin manifest
├── commands/
│   ├── analyze.md                # Analyze command definition
│   ├── critic.md                 # Critic command definition
│   └── hephaestus.md             # Hephaestus command definition
├── references/
│   ├── analyze-schema.json       # Output schema for analyze results
│   ├── critic-schema.json        # Output schema for critic results
│   └── output-schema.json        # Output schema for hephaestus results
├── agents/
│   ├── codex-analyze-agents.md   # Analyze agent persona
│   ├── codex-critic-agents.md    # Critic agent persona
│   └── codex-hephaestus-agents.md # Hephaestus agent persona
└── README.md
```
