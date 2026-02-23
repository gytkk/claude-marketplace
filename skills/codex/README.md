# Codex Plugin

OpenAI Codex CLI integration for Claude Code. Provides two commands:

## Commands

### `/codex:critic`

Code/plan/content review and validation using Codex CLI in non-interactive mode (`codex exec`).

- Validates code changes (git diff), plans, or arbitrary content against user requirements
- Iterative refinement (up to 5 iterations by default)
- Scoring system (0-10) with verdict: pass/warn/fail
- Session-scoped output files: `~/.ai/critic-{SESSION_ID}-result.json`

### `/codex:hephaestus`

Autonomous deep worker for complex implementation tasks.

- Self-directed execution: explore → plan → execute → verify
- Iterative execution (up to 3 iterations by default)
- Self-verification of changes
- Session-scoped output files: `~/.ai/hephaestus-{SESSION_ID}-result.json`

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- Codex authentication (`codex login`)

## Structure

```
skills/codex/
├── .claude-plugin/plugin.json    # Plugin manifest
├── commands/
│   ├── critic.md                 # Critic command definition
│   └── hephaestus.md             # Hephaestus command definition
├── references/
│   ├── critic-schema.json        # Output schema for critic results
│   └── output-schema.json        # Output schema for hephaestus results
├── agents/
│   ├── codex-critic-agents.md    # Critic agent persona
│   └── codex-hephaestus-agents.md # Hephaestus agent persona
└── README.md
```
