#!/bin/bash
# run-reviews.sh - Multi-agent parallel code review
#
# Usage: run-reviews.sh TARGET_DIR [INSTRUCTIONS]
#   TARGET_DIR:   The directory/repository to review (REQUIRED)
#   INSTRUCTIONS: Optional free-form review instructions for this run, e.g.
#                 a target/base branch to diff against or areas to focus on.
#                 May also be supplied via the REVIEW_INSTRUCTIONS env var.
#                 These are appended to the prompt at runtime ONLY -- the
#                 committed prompt template is never modified.
#
# Examples:
#   run-reviews.sh /path/to/project
#   run-reviews.sh /path/to/project "Review against base branch PREX-1553"
#   REVIEW_INSTRUCTIONS="Focus on the new auth flow" run-reviews.sh /path/to/project
#
# Reads config.yaml for a list of agents (each with its own backend + model),
# then spawns them in parallel to review the git changes.
# Results are saved to TARGET_DIR/.reviews/

set -e

# --- Argument validation ---

if [ -z "$1" ]; then
  echo "Error: TARGET_DIR is required"
  echo "Usage: run-reviews.sh /path/to/project"
  echo ""
  echo "The target directory must be the project you want to review,"
  echo "NOT the skill directory."
  exit 1
fi

TARGET_DIR="$1"

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# Optional per-run review instructions. Precedence: 2nd positional arg, then
# the REVIEW_INSTRUCTIONS env var. Appended to the prompt at runtime only.
REVIEW_INSTRUCTIONS="${2:-${REVIEW_INSTRUCTIONS:-}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$TARGET_DIR/.reviews"
PROMPT_FILE="$SKILL_DIR/prompts/review-prompt.md"
CONFIG_FILE="$SKILL_DIR/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Parse config.yaml ---

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
  echo "Create one from config.yaml in the skill directory."
  exit 1
fi

# Parse the agents list from YAML.
# Each agent is a pair of "backend" and "model" lines under the "agents:" key.
BACKENDS=()
MODELS=()
in_agents=false
current_backend=""
current_model=""

flush_agent() {
  if [ -n "$current_backend" ] && [ -n "$current_model" ]; then
    BACKENDS+=("$current_backend")
    MODELS+=("$current_model")
  fi
  current_backend=""
  current_model=""
}

while IFS= read -r line; do
  # Detect the "agents:" key
  if echo "$line" | grep -qE '^agents:'; then
    in_agents=true
    continue
  fi

  # Stop if we hit another top-level key
  if $in_agents && echo "$line" | grep -qE '^[a-zA-Z]'; then
    flush_agent
    in_agents=false
    continue
  fi

  if $in_agents; then
    # New list item starts with "  - "
    if echo "$line" | grep -qE '^[[:space:]]*-[[:space:]]'; then
      # Flush previous agent if any
      flush_agent
      # This line may contain "- backend: value" (compact form)
      if echo "$line" | grep -qE 'backend:'; then
        current_backend=$(echo "$line" | sed 's/.*backend:[[:space:]]*//' | tr -d '"' | tr -d "'")
      fi
      if echo "$line" | grep -qE 'model:'; then
        current_model=$(echo "$line" | sed 's/.*model:[[:space:]]*//' | tr -d '"' | tr -d "'")
      fi
    # Continuation lines within the same list item (indented, no dash)
    elif echo "$line" | grep -qE '^[[:space:]]+[a-zA-Z]'; then
      if echo "$line" | grep -qE 'backend:'; then
        current_backend=$(echo "$line" | sed 's/.*backend:[[:space:]]*//' | tr -d '"' | tr -d "'")
      fi
      if echo "$line" | grep -qE 'model:'; then
        current_model=$(echo "$line" | sed 's/.*model:[[:space:]]*//' | tr -d '"' | tr -d "'")
      fi
    fi
  fi
done < "$CONFIG_FILE"
# Flush the last agent
flush_agent

if [ ${#MODELS[@]} -eq 0 ]; then
  echo -e "${RED}Error: No agents defined in $CONFIG_FILE${NC}"
  exit 1
fi

# --- Validate prerequisites ---

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Multi-Agent Code Review                          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for prompt file
if [ ! -f "$PROMPT_FILE" ]; then
  echo -e "${RED}Error: Review prompt not found at $PROMPT_FILE${NC}"
  exit 1
fi

# Check that required CLIs are available for the backends in use
NEED_CURSOR=false
NEED_OPENCODE=false
NEED_CLAUDE=false
NEED_CODEX=false
for backend in "${BACKENDS[@]}"; do
  case "$backend" in
    cursor)      NEED_CURSOR=true ;;
    opencode)    NEED_OPENCODE=true ;;
    claude-code) NEED_CLAUDE=true ;;
    codex)       NEED_CODEX=true ;;
    *)
      echo -e "${RED}Error: Unknown backend '$backend' in config. Use 'cursor', 'opencode', 'claude-code', or 'codex'.${NC}"
      exit 1
      ;;
  esac
done

if $NEED_CURSOR && ! command -v cursor-agent &> /dev/null; then
  echo -e "${RED}Error: cursor-agent not found. Install from https://cursor.com/cli${NC}"
  exit 1
fi

if $NEED_OPENCODE && ! command -v opencode &> /dev/null; then
  echo -e "${RED}Error: opencode not found. Install from https://opencode.ai${NC}"
  exit 1
fi

if $NEED_CLAUDE && ! command -v claude &> /dev/null; then
  echo -e "${RED}Error: claude not found. Install from https://docs.anthropic.com/en/docs/claude-code${NC}"
  exit 1
fi

if $NEED_CODEX && ! command -v codex &> /dev/null; then
  echo -e "${RED}Error: codex not found. Install with: npm i -g @openai/codex${NC}"
  exit 1
fi

# Verify target directory exists and is a git repo
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo -e "${YELLOW}Warning: $TARGET_DIR does not appear to be a git repository${NC}"
fi

# Setup output directory. NOTE: we deliberately do NOT wipe existing
# review_*.json here. Each agent removes only its OWN output file right
# before it runs (see the launch loop), so a fresh run never destroys
# results a user is still looking at from a previous run.
mkdir -p "$OUTPUT_DIR"

# Write a temporary read-only opencode config into the target project.
# This enforces that review agents (a) cannot edit files and (b) do NOT spin
# up any MCP servers. Every `opencode run` otherwise launches all globally
# configured MCP servers (exa, github, sesame, figma, notebook, ...), each a
# separate long-lived process. With several agents in parallel that balloons
# into dozens of processes that swamp the machine -- and code reviewers never
# need MCP tools (they just read a git diff and write JSON). So we disable
# every MCP server found in the user's global config for the review run.
OPENCODE_CONFIG_DIR="$TARGET_DIR/.opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
OPENCODE_CONFIG_EXISTED=false
mkdir -p "$OPENCODE_CONFIG_DIR"
if [ -f "$OPENCODE_CONFIG_FILE" ]; then
  OPENCODE_CONFIG_EXISTED=true
  cp "$OPENCODE_CONFIG_FILE" "$OPENCODE_CONFIG_FILE.council-backup"
fi

# Locate the user's global opencode config to learn which MCP servers exist.
GLOBAL_OPENCODE_CONFIG=""
for candidate in \
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json" \
  "$HOME/.config/opencode/opencode.json"; do
  if [ -f "$candidate" ]; then
    GLOBAL_OPENCODE_CONFIG="$candidate"
    break
  fi
done

# Build a JSON object that disables every MCP server defined globally. Falls
# back to an empty object if no global config or python3 is available.
MCP_DISABLE_JSON="{}"
if [ -n "$GLOBAL_OPENCODE_CONFIG" ] && command -v python3 &> /dev/null; then
  MCP_DISABLE_JSON=$(GLOBAL_OPENCODE_CONFIG="$GLOBAL_OPENCODE_CONFIG" python3 -c '
import json, os
try:
    with open(os.environ["GLOBAL_OPENCODE_CONFIG"]) as f:
        cfg = json.load(f)
    names = list((cfg.get("mcp") or {}).keys())
    print(json.dumps({n: {"enabled": False} for n in names}))
except Exception:
    print("{}")
')
fi

# Emit the review config. The "mcp" block disables every server by name so no
# MCP processes are spawned for the duration of the review.
cat > "$OPENCODE_CONFIG_FILE" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": "deny",
    "bash": {
      "*": "allow"
    }
  },
  "agent": {
    "build": {
      "tools": { "write": false, "edit": false }
    }
  },
  "mcp": $MCP_DISABLE_JSON
}
EOF

# Track spawned agent PIDs so we can wait on them.
PIDS=()

# Ensure cleanup on exit/interrupt.
#
# opencode (and some other backends) detach a server/worker that reparents to
# launchd (PID 1), so signalling the script's child PIDs or process group is
# not enough -- those processes escape and pile up. Instead we sweep by the
# unique target path that every agent for THIS review carries on its command
# line (opencode `--dir=$TARGET_DIR`, cursor `--workspace=$TARGET_DIR`). That
# precisely targets this run's processes (and any they detached) without
# touching the user's other agent sessions or this script's own shell.
sweep_agents() {
  local sig="$1"
  # 1) Kill the backgrounded job PIDs we launched and their direct children.
  #    This handles backends that carry no identifying path flag (claude-code
  #    runs after a `cd`, codex has no workspace flag).
  local pid child
  for pid in "${PIDS[@]}"; do
    [ -z "$pid" ] && continue
    for child in $(pgrep -P "$pid" 2>/dev/null); do
      kill "-$sig" "$child" 2>/dev/null || true
    done
    kill "-$sig" "$pid" 2>/dev/null || true
  done
  # 2) Sweep by the unique target path that opencode/cursor agents carry on
  #    their command line. This catches opencode's detached server/worker that
  #    reparents to launchd and would otherwise escape. The path is specific to
  #    this review, so the user's other agent sessions are untouched.
  pkill "-$sig" -f -- "--dir=$TARGET_DIR" 2>/dev/null || true
  pkill "-$sig" -f -- "--workspace=$TARGET_DIR" 2>/dev/null || true
}

_CLEANUP_DONE=false
cleanup() {
  # Never let errexit abort cleanup partway through.
  set +e
  # Guard against running twice (e.g. a signal trap followed by the EXIT trap).
  if [ "$_CLEANUP_DONE" = true ]; then
    return
  fi
  _CLEANUP_DONE=true

  # Terminate any still-running agents for this target (and anything they
  # detached). Gentle first, then force.
  sweep_agents TERM
  sleep 1
  sweep_agents KILL

  # Restore the target project's opencode config to its original state.
  if [ "$OPENCODE_CONFIG_EXISTED" = true ]; then
    mv "$OPENCODE_CONFIG_FILE.council-backup" "$OPENCODE_CONFIG_FILE" 2>/dev/null
  else
    rm -f "$OPENCODE_CONFIG_FILE"
    rmdir "$OPENCODE_CONFIG_DIR" 2>/dev/null || true
  fi
}

# On a fatal signal, run cleanup then exit non-zero so the EXIT trap's
# second invocation is a no-op (guarded above).
on_signal() {
  cleanup
  exit 130
}
trap cleanup EXIT
trap on_signal INT TERM HUP

echo "Prompt:  $PROMPT_FILE"
echo "Output:  $OUTPUT_DIR"
echo -e "Target:  ${GREEN}$TARGET_DIR${NC}"
if [ -n "$REVIEW_INSTRUCTIONS" ]; then
  echo -e "Extra:   ${YELLOW}$REVIEW_INSTRUCTIONS${NC}"
fi
echo ""
echo "Agents:"
for i in "${!MODELS[@]}"; do
  echo -e "  ${CYAN}${BACKENDS[$i]}${NC} / ${MODELS[$i]}"
done
echo ""
echo "Starting parallel reviews..."
echo ""

# Read prompt
PROMPT="$(cat "$PROMPT_FILE")"

# Append any per-run instructions so reviewers see them as part of the prompt.
if [ -n "$REVIEW_INSTRUCTIONS" ]; then
  PROMPT="$PROMPT

## Additional Instructions For This Review

The following instructions are specific to this review run and take
precedence over the general guidance above where they conflict:

$REVIEW_INSTRUCTIONS"
fi

# --- Launch agents in parallel ---

# Sanitize model name for use as a filename (replace / with __)
sanitize_model() {
  echo "$1" | tr '/' '__'
}

SANITIZED_MODELS=()
for i in "${!MODELS[@]}"; do
  model="${MODELS[$i]}"
  backend="${BACKENDS[$i]}"
  safe_name=$(sanitize_model "$model")
  SANITIZED_MODELS+=("$safe_name")

  # Remove only THIS agent's previous output (if any) so a rerun overwrites
  # its own file without destroying other agents' or other runs' results.
  rm -f "$OUTPUT_DIR/review_${safe_name}.json"

  echo "  ⏳ Starting: $model ($backend)"

  case "$backend" in
    cursor)
      (
        REVIEW_OUTPUT_FILE="$OUTPUT_DIR/review_${safe_name}.json" \
        cursor-agent -p --mode=plan --force --workspace="$TARGET_DIR" --model="$model" "$PROMPT" \
          > /dev/null 2>&1
      ) &
      ;;
    opencode)
      (
        REVIEW_OUTPUT_FILE="$OUTPUT_DIR/review_${safe_name}.json" \
        opencode run --model="$model" --dir="$TARGET_DIR" "$PROMPT" \
          > /dev/null 2>&1
      ) &
      ;;
    claude-code)
      (
        cd "$TARGET_DIR"
        REVIEW_OUTPUT_FILE="$OUTPUT_DIR/review_${safe_name}.json" \
        claude -p --permission-mode plan --model "$model" "$PROMPT" \
          > /dev/null 2>&1
      ) &
      ;;
    codex)
      (
        REVIEW_OUTPUT_FILE="$OUTPUT_DIR/review_${safe_name}.json" \
        codex exec --sandbox read-only --model "$model" "$PROMPT" \
          > /dev/null 2>&1
      ) &
      ;;
  esac

  PIDS+=($!)
done

echo ""
echo "Waiting for reviews to complete (this may take 1-3 minutes)..."
echo ""

# Wait for all processes and check output files
COMPLETED=0
FAILED=0
for i in "${!PIDS[@]}"; do
  wait "${PIDS[$i]}"
  safe_name="${SANITIZED_MODELS[$i]}"
  outfile="$OUTPUT_DIR/review_${safe_name}.json"
  if [ -s "$outfile" ] && jq empty "$outfile" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Completed: ${MODELS[$i]} (${BACKENDS[$i]})"
    COMPLETED=$((COMPLETED + 1))
  else
    echo -e "  ${RED}✗${NC} Failed: ${MODELS[$i]} (${BACKENDS[$i]})"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

if [ $COMPLETED -eq 0 ]; then
  echo -e "${RED}All reviews failed.${NC}"
  exit 1
fi

echo -e "${GREEN}Done!${NC} $COMPLETED succeeded, $FAILED failed"
echo ""
echo "Results:"
for i in "${!MODELS[@]}"; do
  safe_name="${SANITIZED_MODELS[$i]}"
  if [ -s "$OUTPUT_DIR/review_${safe_name}.json" ]; then
    echo "  - $OUTPUT_DIR/review_${safe_name}.json"
  fi
done
echo ""
