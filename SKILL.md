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

The user's project directory is where they started their agent session - NOT this skill's directory. Look for the git repository path in the conversation context (e.g., `/Users/.../git/jupyter_server`).

## Workflow

### Step 1: Identify the Target Repository

Determine the user's project directory from the conversation context. This is typically shown at the start of the session or can be found by checking where `AGENTS.md`, `CLAUDE.md`, or similar agent guidance is located. It is NOT `/Users/.../skills/council/`.

### Step 2: Run Parallel Reviews

Run this skill's review script and **pass the user's project directory as an argument**:

```bash
~/.agents/skills/council/scripts/run-reviews.sh /path/to/users/project
```

**IMPORTANT**: Always pass the full path to the user's project as the first argument.

#### Passing review instructions (target branch, focus areas, etc.)

If the user wants the review scoped or focused -- most commonly a **target/base
branch** to diff against, but also things like "focus on the auth flow" or
"ignore test files" -- pass those as an optional second argument (or via the
`REVIEW_INSTRUCTIONS` env var). They are appended to the prompt at runtime only;
the committed prompt template is never edited.

```bash
# Review a PR against its actual base branch
~/.agents/skills/council/scripts/run-reviews.sh /Users/you/git/project "Review the changes on this branch against base branch XYZ (use 'git diff XYZ...HEAD'), not main."

# Focus the review
~/.agents/skills/council/scripts/run-reviews.sh /Users/you/git/project "Focus on security of the new upload endpoint; skip style nits."
```

Ask the user for the base branch when reviewing a PR, since the default prompt
diffs against `main`. Do NOT edit `prompts/review-prompt.md` to inject per-run
context -- use this argument instead.

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

All configuration lives in `~/.agents/skills/council/config.yaml`:

```yaml
# Each agent specifies its own backend and model.
# Mix and match all four backends freely.
agents:
  - backend: claude-code
    model: sonnet

  - backend: codex
    model: gpt-5.3-codex

  - backend: opencode
    model: google/gemini-3.1-pro
```
