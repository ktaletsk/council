# council

> **Ensemble code reviews.** Run the same review prompt against multiple AI 
> agents in parallel, then synthesize their findings into one comprehensive 
> report — because different models catch different bugs.

[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)](https://code.claude.com/docs/en/skills)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Why This Exists

No single AI model catches everything. GPT might spot a race condition that 
Opus misses, while Gemini flags a performance issue neither noticed. By running 
the same critical review prompt against multiple agents and combining their 
findings, you get more thorough coverage than any single model provides.

| | Single Model Review | council |
|---|---|---|
| One perspective | Yes | Multiple perspectives |
| Model-specific blind spots | Possible | Cross-validated findings |
| Fast | Yes | Parallel but slower |
| Simple | Yes | Needs at least one supported CLI |

## How It Works

1. **Parallel Execution** — Spawns multiple agent processes simultaneously, each via its configured backend
2. **Independent Reviews** — Each agent reviews staged git changes in read-only mode
3. **Synthesis** — The host agent combines outputs into a single deduplicated report

### Supported Backends

| Backend | CLI Tool | Model Format | Requirement |
|---------|----------|-------------|-------------|
| **Claude Code** | `claude -p` | Alias (`sonnet`, `opus`) or full name | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + Anthropic account |
| **Codex** | `codex exec` | Model name (e.g. `gpt-5-codex`) | [Codex CLI](https://github.com/openai/codex) (`npm i -g @openai/codex`) + ChatGPT plan or API key |
| **OpenCode** | `opencode run` | `provider/model` (e.g. `google/gemini-3-pro`) | [OpenCode CLI](https://opencode.ai) + provider API keys |
| **Cursor** | `cursor-agent` | Model name (e.g. `gemini-3.1-pro`) | [Cursor CLI](https://cursor.com/cli) + subscription |

Backends can be mixed freely — run Claude through Claude Code, GPT through
Codex, and Gemini through OpenCode all in the same review session.

## Installation

### Personal skill (all projects)

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/ktaletsk/council ~/.claude/skills/council
```

### Project skill (specific project)

```bash
mkdir -p .claude/skills
git clone https://github.com/ktaletsk/council .claude/skills/council
```

## Requirements

**One or more** of the following:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`) with an Anthropic account
- [Codex CLI](https://github.com/openai/codex) (`codex`) with a ChatGPT plan or OpenAI API key
- [OpenCode CLI](https://opencode.ai) (`opencode`) with provider API keys configured
- [Cursor CLI](https://cursor.com/cli) (`cursor-agent`) with an active Cursor subscription

Plus:

- A host agent (Claude Code, OpenCode, etc.) for synthesis

## Configuration

All settings are in `config.yaml` at the skill root. Each agent entry specifies
its own backend and model, so you can mix and match freely:

```yaml
agents:
  - backend: claude-code
    model: sonnet

  - backend: codex
    model: gpt-5-codex

  - backend: opencode
    model: google/gemini-3-pro
```

### All Claude Code

```yaml
agents:
  - backend: claude-code
    model: opus
  - backend: claude-code
    model: sonnet
  - backend: claude-code
    model: haiku
```

### All Codex

```yaml
agents:
  - backend: codex
    model: gpt-5-codex
  - backend: codex
    model: gpt-5.1-codex
```

### All OpenCode

```yaml
agents:
  - backend: opencode
    model: anthropic/claude-sonnet-4-20250514
  - backend: opencode
    model: openai/gpt-5.1-codex
  - backend: opencode
    model: google/gemini-3-pro
```

### All Cursor

```yaml
agents:
  - backend: cursor
    model: opus-4.6-thinking
  - backend: cursor
    model: gpt-5.3-codex-high
  - backend: cursor
    model: gemini-3.1-pro
```

### Discover available models

```bash
# Claude Code (aliases: sonnet, opus, haiku, or full model names)
claude --model

# Codex
codex    # then /model inside the TUI

# OpenCode
opencode models

# Cursor
cursor-agent --list-models
```

## Usage

Start a code review:

```
/council
```

Or trigger naturally:

```
Review my staged changes
```

```
Run a council review
```

## Example Session

```
You: /council

Claude: I'll run parallel code reviews using multiple AI agents.

Running reviews on /Users/you/project...

  Agents:
    claude-code / sonnet
    codex       / gpt-5-codex
    opencode    / google/gemini-3-pro

  ⏳ Starting: sonnet (claude-code)
  ⏳ Starting: gpt-5-codex (codex)
  ⏳ Starting: google/gemini-3-pro (opencode)

Waiting for reviews to complete (this may take 1-3 minutes)...

  ✓ Completed: sonnet (claude-code)
  ✓ Completed: gpt-5-codex (codex)
  ✓ Completed: google/gemini-3-pro (opencode)

Now synthesizing results...

# Code Review Report

## Summary
The changes introduce timestamp handling improvements with proper
fallback logic. All 3 reviewers found issues worth addressing.

[continued...]
```

## Output

Results are saved to your project's `.reviews/` directory:

```
<your-project>/.reviews/
├── review_sonnet.json
├── review_gpt-5-codex.json
├── review_google__gemini-3-pro.json
└── COMBINED_REVIEW.md
```

## Customization

### Change Review Focus

Edit `prompts/review-prompt.md` to adjust:
- What aspects to focus on (security, performance, etc.)
- Output format
- How critical the review should be

### Thinking Depth

Add keywords to `prompts/review-prompt.md`:
- `think` — basic reasoning
- `think hard` — more thorough  
- `think harder` — very thorough
- `ultrathink` — maximum depth (slower)

## Files

```
council/
├── SKILL.md              # Skill definition for Claude Code
├── README.md             # This file
├── config.yaml           # Agent backend + model configuration
├── scripts/
│   └── run-reviews.sh    # Parallel review runner
└── prompts/
    └── review-prompt.md  # Review prompt template
```

## Compatibility

This skill uses the open [Agent Skills](https://agentskills.io) standard and should work with:
- Claude Code (`~/.claude/skills/`)
- OpenCode (`.opencode/skills/`)
- Codex (`.codex/skills/`)
- Cursor (`.cursor/skills/`)
- VS Code, GitHub Copilot, and other compatible agents

## License

MIT
