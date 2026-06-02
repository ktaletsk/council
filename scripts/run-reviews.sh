#!/bin/bash
# run-reviews.sh - Multi-agent parallel code review
#
# Usage: run-reviews.sh TARGET_DIR
#   TARGET_DIR: The directory/repository to review (REQUIRED)
#
# Reads config.yaml for a list of agents (each with its own backend + model),
# then spawns them in parallel to review staged git changes.
# Results are saved to TARGET_DIR/.reviews/

set -e

# Enable job control so each backgrounded agent becomes the leader of its
# own process group. This lets us kill an agent and ALL of its forked
# children (opencode spawns server/worker subprocesses) via the group,
# without ever signalling this script's own process group (which is shared
# with the caller's interactive shell). macOS ships bash 3.2 with no
# setsid, so `set -m` is the portable way to get per-job process groups.
set -m

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

# Setup output directory
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/review_*.json

# Write a temporary read-only opencode config into the target project.
# This enforces that all opencode agents spawned for review cannot edit files.
OPENCODE_CONFIG_DIR="$TARGET_DIR/.opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
OPENCODE_CONFIG_EXISTED=false
mkdir -p "$OPENCODE_CONFIG_DIR"
if [ -f "$OPENCODE_CONFIG_FILE" ]; then
  OPENCODE_CONFIG_EXISTED=true
  cp "$OPENCODE_CONFIG_FILE" "$OPENCODE_CONFIG_FILE.council-backup"
fi
cat > "$OPENCODE_CONFIG_FILE" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
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
  }
}
EOF

# Track spawned agent PIDs so we can reap them (and their child
# process groups) if this script is interrupted or exits early.
PIDS=()

# Ensure cleanup on exit: kill any still-running agents, then restore config.
# Recursively collect a PID and all of its descendant PIDs.
# Backends like opencode fork/re-exec into their own process group,
# so killing the job's PID alone (or its assumed PGID) can miss the
# real worker and its server children. Walking the process tree is the
# portable way to guarantee nothing is left behind.
collect_descendants() {
  local parent="$1"
  echo "$parent"
  local child
  for child in $(pgrep -P "$parent" 2>/dev/null); do
    collect_descendants "$child"
  done
}

kill_tree() {
  local sig="$1"; shift
  local root
  local self_pgid
  # The process group we must NEVER signal: our own (shared with the caller).
  self_pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
  for root in "$@"; do
    [ -z "$root" ] && continue
    # With `set -m`, each backgrounded agent is a process-group leader, so the
    # job PID equals its PGID. Killing that group reaches the agent and every
    # subprocess it forked (e.g. opencode's server/workers).
    local pgid
    pgid=$(ps -o pgid= -p "$root" 2>/dev/null | tr -d ' ')
    if [ -n "$pgid" ] && [ "$pgid" != "$self_pgid" ]; then
      kill "-$sig" "-$pgid" 2>/dev/null || true
    fi
    # Belt-and-suspenders: also walk the visible descendant tree by PID, but
    # only if the group kill was unavailable (pgid empty or == our own group).
    if [ -z "$pgid" ] || [ "$pgid" = "$self_pgid" ]; then
      local p
      for p in $(collect_descendants "$root"); do
        [ "$p" = "$$" ] && continue
        kill "-$sig" "$p" 2>/dev/null || true
      done
    fi
  done
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

  # Terminate every spawned agent along with all of its descendants and
  # process group. This prevents orphaned `opencode run` (and similar)
  # processes from accumulating when the script exits or is interrupted.
  if [ "${#PIDS[@]}" -gt 0 ]; then
    kill_tree TERM "${PIDS[@]}"
    sleep 1
    kill_tree KILL "${PIDS[@]}"
  fi

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

# --- Launch agents in parallel ---

# Sanitize model name for use as a filename (replace / with __)
sanitize_model() {
  echo "$1" | tr '/' '__'
}

# Maximum number of agents to run concurrently. Launching all agents at once
# (each opencode agent forks several subprocesses) can overwhelm the machine,
# so we throttle to MAX_PARALLEL in flight at a time. Override via env if you
# have a beefier box, e.g. MAX_PARALLEL=8 run-reviews.sh ...
MAX_PARALLEL="${MAX_PARALLEL:-4}"

# Block until fewer than MAX_PARALLEL background jobs are running.
throttle() {
  # `jobs -p -r` lists PIDs of currently running background jobs.
  while [ "$(jobs -p -r 2>/dev/null | wc -l | tr -d ' ')" -ge "$MAX_PARALLEL" ]; do
    # Wait for at least one job to finish, then re-check. `wait -n` is not in
    # bash 3.2, so fall back to a short sleep poll.
    sleep 0.5
  done
}

SANITIZED_MODELS=()
for i in "${!MODELS[@]}"; do
  model="${MODELS[$i]}"
  backend="${BACKENDS[$i]}"
  safe_name=$(sanitize_model "$model")
  SANITIZED_MODELS+=("$safe_name")
  # Respect the concurrency cap before spawning the next agent.
  throttle

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
