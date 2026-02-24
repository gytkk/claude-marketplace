# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code Plugin Marketplace — a registry of Claude Code extensions including skill plugins and LSP (Language Server Protocol) plugins. This is a **metadata/configuration repository** with no build system, no package manager, and no test framework.

## Repository Structure

```
.claude-plugin/marketplace.json   # Central plugin registry (marketplace schema)
skills/codex/                     # Codex MCP integration skill (v2.1.0)
  ├── .claude-plugin/plugin.json  # Plugin manifest (name, version)
  ├── commands/*.md               # Skill definitions (YAML frontmatter + markdown)
  ├── agents/*.md                 # Agent personas (inlined into developer-instructions)
  └── references/*.json           # JSON output schemas
lsp/                              # Language server plugins
  ├── metals-lsp/                 # Scala (Metals)
  ├── ty-lsp/                     # Python type checking (Astral ty)
  ├── terraform-ls/               # Terraform
  └── nixd-lsp/                   # Nix
```

## Architecture

### Plugin Registry

`marketplace.json` follows the `https://anthropic.com/claude-code/marketplace.schema.json` schema. Each plugin entry references a `source` directory containing its own `plugin.json` manifest.

### Codex Skills (MCP-based)

Three commands all follow the same execution pattern:

1. Prerequisites check (`codex` CLI installed)
2. Gather context (file paths only — Codex accesses files via `cwd`)
3. MCP invocation via `mcp__codex__codex` with separate parameters: `prompt` (< 500 chars), `developer-instructions` (agent persona), `base-instructions` (output schema)
4. Iterative refinement via `mcp__codex__codex-reply` using `threadId`
5. Save results to `~/.ai/{command}-{SESSION_ID}-result.json`

| Command | Purpose | Sandbox | Max Iterations |
|---------|---------|---------|----------------|
| `/codex:analyze` | Deep analysis | read-only | 3 |
| `/codex:hephaestus` | Autonomous implementation | workspace-write | 3 |
| `/codex:critic` | Code review & verification | read-only | 5 |

Key constraint: `prompt` parameter must be under 500 characters. File content is never embedded — Codex reads files directly via `cwd`.

### LSP Plugins

Each LSP plugin has a `plugin.json` mapping file extensions to language IDs and specifying the server command. No custom code — purely configuration.

## Conventions

### Skill Command Files (`commands/*.md`)

- YAML frontmatter: `description`, `argument-hint`, `allowed-tools`
- Body: step-by-step execution instructions with user visibility rules
- Output: strict JSON (no fences) matching the corresponding `references/*.json` schema
- Agent personas are embedded verbatim in `developer-instructions` parameter

### Output Schemas

All Codex commands enforce conciseness limits:
- `summary` ≤ 100 chars
- Issue `description` ≤ 80 chars, `suggestion` ≤ 80 chars
- Finding `title` ≤ 50 chars, `evidence` ≤ 80 chars

### Commit Style

Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`. Use `feat!:` for breaking changes.

### Version Management

**Every change to a plugin's commands, agents, references, or configuration MUST include a version bump.**
Without a version bump, the marketplace cache will not update and changes will not take effect for users.

Plugin versions are tracked in two places that must stay in sync:
- `skills/codex/.claude-plugin/plugin.json` → authoritative version
- `.claude-plugin/marketplace.json` → registry version

When bumping versions, update **both files** in the same commit. Use semver:
- **patch** (e.g., 2.2.0 → 2.2.1): bug fixes, wording tweaks
- **minor** (e.g., 2.2.0 → 2.3.0): new features, visibility changes, schema additions
- **major** (e.g., 2.3.0 → 3.0.0): breaking changes to output schema or command interface
