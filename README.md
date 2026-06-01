# council

> **Ensemble code reviews.** Run the same review prompt against multiple AI 
> agents in parallel, then synthesize their findings into one comprehensive 
> report — because different models catch different bugs.

[![AI Agent Skill](https://img.shields.io/badge/AI%20Agent-Skill-blueviolet)](https://agentskills.io)
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
| **Claude Code** | `claude -p` | Alias (`sonnet`, `opus`) or full name | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + Anthropic account (`claude -p` draws from a separate Agent SDK credit, not your interactive Pro/Max limit — see note below) |
| **Codex** | `codex exec` | Model name (e.g. `gpt-5.3-codex`) | [Codex CLI](https://github.com/openai/codex) (`npm i -g @openai/codex`) + ChatGPT plan or API key |
| **OpenCode** | `opencode run` | `provider/model` (e.g. `google/gemini-3.1-pro`) | [OpenCode CLI](https://opencode.ai) + provider API keys |
| **Cursor** | `cursor-agent` | Model name (e.g. `gemini-3.1-pro`) | [Cursor CLI](https://cursor.com/cli) + subscription |

Backends can be mixed freely — run Claude through Claude Code, GPT through
Codex, and Gemini through OpenCode all in the same review session.

### Use the subscriptions and credits you already have

council drives whichever agent CLIs are already installed and authenticated on
your machine, so most reviewers bill against access you're already paying for:

- **Codex** uses your **ChatGPT Plus/Pro/Team** plan (or an OpenAI API key).
- **Cursor** runs through your active **Cursor subscription** — the models in
  `cursor-agent models` are included in your plan.
- **OpenCode** uses whatever providers you've configured, including its own
  **free models** (e.g. `opencode/big-pickle`) that cost nothing at all.

> **Heads up on the `claude-code` backend.** council invokes Claude Code in
> non-interactive mode (`claude -p`), and that is **not** simply covered by your
> normal Pro/Max usage the way interactive Claude Code is. Per Anthropic, as of
> **June 15, 2026** `claude -p` (and the Agent SDK) stop drawing from your
> interactive subscription limits and instead draw from a separate, capped
> **monthly Agent SDK credit** you have to opt into once — $20 on Pro, $100 on
> Max 5x, $200 on Max 20x. When that credit runs out, requests fall through to
> pay-as-you-go API billing (if you've enabled usage credits) or stop until the
> credit refreshes. In other words, you **cannot easily run a large council on
> the `claude-code` backend off a Pro/Max plan** — budget for the Agent SDK
> credit or an API key, or prefer the other backends. See
> [Use the Claude Agent SDK with your Claude plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan).
> (You can still get Claude models without this caveat by running them through
> the **Cursor** or **OpenCode** backends instead.)

Because backends mix freely, you can assemble a multi-model council almost
entirely from plans you already subscribe to — for example, Opus via Cursor,
GPT via your ChatGPT plan through Codex, and a couple of free OpenCode models —
without provisioning a single new API key. If a CLI isn't installed or signed
in, council simply skips that reviewer; just configure the ones you have.

## Installation

The default path is the **Skills CLI** (`npx skills`): it pulls this repo from
GitHub and installs into the right agent skill directories for Cursor and many
other AI coding agents. You need [Node.js](https://nodejs.org/) so `npx` is
available.

### Recommended: `npx skills`

**All projects (global / user-level):**

```bash
npx skills add ktaletsk/council -g
```

**This repository only (from inside the project):**

```bash
npx skills add ktaletsk/council
```

Use `-a <agent>` to target specific agents (e.g. `-a cursor`), or run without
it and follow the prompts. To update later: `npx skills update` (add `-g` for
global installs). More skills: [skills.sh](https://skills.sh/).

### Manual: `git clone`

If you prefer to place the skill yourself:

**Personal skill (all projects)**

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/ktaletsk/council ~/.claude/skills/council
```

**Project skill (specific project)**

```bash
mkdir -p .claude/skills
git clone https://github.com/ktaletsk/council .claude/skills/council
```

## Requirements

**One or more** of the following:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`) with an Anthropic account — note that council uses `claude -p`, which bills against the Agent SDK monthly credit (or API), not your interactive Pro/Max usage; see [Use the subscriptions and credits you already have](#use-the-subscriptions-and-credits-you-already-have)
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
    model: gpt-5.3-codex

  - backend: opencode
    model: google/gemini-3.1-pro
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
    model: gpt-5.5
  - backend: codex
    model: gpt-5.3-codex
```

### All OpenCode

```yaml
agents:
  - backend: opencode
    model: amazon-bedrock/us.anthropic.claude-opus-4-8
  - backend: opencode
    model: amazon-bedrock/zai.glm-5
  - backend: opencode
    model: opencode/big-pickle   # free
```

### All Cursor

```yaml
agents:
  - backend: cursor
    model: claude-opus-4-8-thinking-high
  - backend: cursor
    model: gpt-5.5-high
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

Agent: I'll run parallel code reviews using multiple AI agents.

Running reviews on /Users/you/project...

  Agents:
    claude-code / sonnet
    codex       / gpt-5.3-codex
    opencode    / google/gemini-3.1-pro

  ⏳ Starting: sonnet (claude-code)
  ⏳ Starting: gpt-5.3-codex (codex)
  ⏳ Starting: google/gemini-3.1-pro (opencode)

Waiting for reviews to complete (this may take 1-3 minutes)...

  ✓ Completed: sonnet (claude-code)
  ✓ Completed: gpt-5.3-codex (codex)
  ✓ Completed: google/gemini-3.1-pro (opencode)

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
├── review_gpt-5.3-codex.json
├── review_google__gemini-3.1-pro.json
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
├── SKILL.md              # Agent Skills definition
├── README.md             # This file
├── config.yaml           # Agent backend + model configuration
├── scripts/
│   └── run-reviews.sh    # Parallel review runner
└── prompts/
    └── review-prompt.md  # Review prompt template
```

## Compatibility

This skill is distributed through [skills.sh](https://skills.sh/ktaletsk/council)
and uses the open [Agent Skills](https://agentskills.io) standard. It should
work with:
- Claude Code (`~/.claude/skills/`)
- OpenCode (`.opencode/skills/`)
- Codex (`.codex/skills/`)
- Cursor (`.cursor/skills/`)
- VS Code, GitHub Copilot, and other compatible agents

## License

MIT
