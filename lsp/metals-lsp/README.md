# metals-lsp

Scala language server ([Metals](https://scalameta.org/metals/)) plugin for Claude Code.

## Prerequisites

The `metals` binary must be available on your `PATH`.

### Installation

```bash
# macOS (Homebrew)
brew install metals

# Coursier
cs install metals

# Nix
nix-env -iA nixpkgs.metals
```

## Supported file types

| Extension | Language |
|-----------|----------|
| `.scala` | Scala |
| `.sc` | Scala |
| `.sbt` | SBT |
| `.worksheet.sc` | Scala |

## Usage

```bash
claude plugin marketplace add gytkk/claude-marketplace
claude plugin install metals-lsp@gytkk
```
