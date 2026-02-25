---
name: council
description: Run parallel code reviews with multiple AI agents, then synthesize into one report. Triggers on "review code" or "council review".
---

# Council Code Review Skill

This skill runs the same code review prompt against multiple AI agents in parallel, then synthesizes their findings into a single comprehensive report. It supports **Claude Code**, **Codex CLI**, **OpenCode**, and **Cursor** as agent backends -- and you can mix them freely.

## When to Use

Activate this skill when the user asks to:
- "Review my code"
- "Run a code review"
- "Review the staged changes"
- "Do a council review"
- "Get multiple perspectives on this code"

## CRITICAL: Target Directory

**You must pass the USER'S PROJECT DIRECTORY as an argument to the script.**

The user's project directory is where they started their Claude Code session - NOT this skill's directory. Look for the git repository path in the conversation context (e.g., `/Users/.../git/jupyter_server`).

## Workflow

### Step 1: Identify the Target Repository

Determine the user's project directory from the conversation context. This is typically shown at the start of the session or can be found by checking where CLAUDE.md is located. It is NOT `/Users/.../skills/council/`.

### Step 2: Run Parallel Reviews

Run the review script and **pass the user's project directory as an argument**:

```bash
~/.claude/skills/council/scripts/run-reviews.sh /path/to/users/project
```

For example, if the user is working in `/Users/ktaletskiy/git/jupyter_server`:
```bash
~/.claude/skills/council/scripts/run-reviews.sh /Users/ktaletskiy/git/jupyter_server
```

**IMPORTANT**: Always pass the full path to the user's project as the first argument.

The script reads `config.yaml` from the skill directory to determine which agents to run. Each agent entry specifies its own **backend** and **model**, so you can mix and match freely across all four supported backends.

This will:
- Run all configured agents in parallel, each via its own backend
- Save individual JSON results to `<project>/.reviews/`
- Take 1-3 minutes depending on code size

### Step 3: Synthesize Results

After the script completes, read all JSON files from `<project>/.reviews/` (in the user's project directory) and synthesize them into a combined report.

**Synthesis Rules:**
1. Do NOT mention which agent found which issue
2. Deduplicate similar issues (same file + same line + same problem = one entry)
3. If reviewers disagree on severity, use the higher severity
4. Preserve unique findings from each reviewer
5. Present findings as if from a single thorough review

**Output Format:**

Write the combined report to `<project>/.reviews/COMBINED_REVIEW.md` using this structure:

```markdown
# Code Review Report

**Repository:** [repo name from user's directory]
**Date:** [today's date]

---

## Summary

[1-2 paragraph summary]

**Consensus:** [X of Y reviewers recommended changes / approved]

---

## Critical Issues (Require Action)

### 1. [Issue Title]
**Severity:** 🔴 HIGH
**File:** `path/to/file` (line X)

[Description]

**Recommendation:** [How to fix]

---

## Medium Issues (Should Address)

[Same format, 🟠 MEDIUM]

## Low Issues (Consider Addressing)

[Same format, 🟡 LOW]

## Suggested Improvements

[Numbered list]

---

## Verdict

**[🔴 REQUEST CHANGES / 🟢 APPROVE]**

[Priority action items table]
```

### Step 4: Report to User

After writing the combined report, summarize the key findings:
- Total issues found (by severity)
- Top 3 priority items to address
- Overall verdict

## Configuration

All configuration lives in `~/.claude/skills/council/config.yaml`:

```yaml
# Each agent specifies its own backend and model.
# Mix and match all four backends freely.
agents:
  - backend: claude-code
    model: sonnet

  - backend: codex
    model: gpt-5-codex

  - backend: opencode
    model: google/gemini-3-pro
```

### Backends

Each agent entry requires a `backend` and a `model`:

| Backend | CLI command | `model` format | Requires |
|---------|-----------|---------------|----------|
| `claude-code` | `claude -p` | Alias (`sonnet`, `opus`) or full name (`claude-sonnet-4-20250514`) | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + Anthropic account |
| `codex` | `codex exec` | Model name (e.g. `gpt-5-codex`) | [Codex CLI](https://github.com/openai/codex) + ChatGPT plan or API key |
| `opencode` | `opencode run` | `provider/model` (e.g. `anthropic/claude-sonnet-4-20250514`) | [OpenCode CLI](https://opencode.ai) + provider API keys |
| `cursor` | `cursor-agent` | Model name (e.g. `gemini-3.1-pro`) | [Cursor CLI](https://cursor.com/cli) + subscription |

### Discovering available models

- **Claude Code**: `claude --model` (aliases: `sonnet`, `opus`, `haiku`)
- **Codex**: `/model` inside `codex` TUI, or see [Codex models docs](https://developers.openai.com/codex/models)
- **OpenCode**: `opencode models`
- **Cursor**: `cursor-agent --list-models`

### Other customization

- **Review focus**: Edit `~/.claude/skills/council/prompts/review-prompt.md`
- **Thinking depth**: Add "think hard" or "ultrathink" to the prompt

## Files

```
~/.claude/skills/council/
├── SKILL.md              # This file
├── config.yaml           # Backend and model configuration
├── scripts/
│   └── run-reviews.sh    # Parallel review runner
└── prompts/
    └── review-prompt.md  # Review prompt template

# Output is saved to the user's project:
<project>/.reviews/
├── review_*.json         # Individual agent outputs
└── COMBINED_REVIEW.md    # Synthesized report
```
