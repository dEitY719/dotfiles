# Bash Commands -- implementation details for each execution step

## Step 1: Validate Preconditions

```bash
# Must be inside a git repo
git rev-parse --show-toplevel

# Must NOT be inside an existing worktree -- block if so
GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"
if [[ "$GIT_DIR" != "$GIT_COMMON" ]]; then
  echo "Error: Cannot spawn from inside a worktree. Run from the main repository."
  exit 1
fi

# Warn on dirty state (do not block)
git diff --quiet || echo "Warning: uncommitted changes in working directory"

# Check parent directory is writable
PARENT="$(dirname "$(git rev-parse --show-toplevel)")"
test -w "$PARENT" || { echo "Error: Permission denied: $PARENT"; exit 1; }
```

## Step 2: Detect AI Agent

```bash
detect_ai_agent() {
  # Priority 1: --agent argument (passed as $1)
  if [[ -n "${1:-}" ]]; then
    echo "$1"
    return
  fi

  # Priority 2: AI_AGENT_NAME env var
  if [[ -n "${AI_AGENT_NAME:-}" ]]; then
    echo "$AI_AGENT_NAME"
    return
  fi

  # Priority 3: Agent-specific env vars
  if [[ "${CLAUDECODE:-}" == "1" ]]; then echo "claude"; return; fi
  if [[ "${GEMINI_CLI:-}" == "1" ]]; then echo "gemini"; return; fi
  if [[ "${CODEX_CLI:-}" == "1" ]]; then echo "codex"; return; fi
  if [[ "${OPENCODE:-}" == "1" ]]; then echo "opencode"; return; fi
  if [[ "${CURSOR:-}" == "1" || "${TERM_PROGRAM:-}" == "cursor" ]]; then echo "cursor"; return; fi
  if [[ "${GITHUB_COPILOT:-}" == "1" ]]; then echo "copilot"; return; fi

  # Priority 4: Fallback
  echo "agent"
}

AGENT="$(detect_ai_agent "${AGENT_OVERRIDE:-}")"
```

## Step 1.5: Detect git-crypt

```bash
# Check if repo uses git-crypt by looking for .gitattributes filter entries
GIT_CRYPT_ACTIVE=false
if git config --get filter.git-crypt.smudge >/dev/null 2>&1; then
  GIT_CRYPT_ACTIVE=true
fi

# Build git-crypt bypass flags for worktree creation
GIT_CRYPT_FLAGS=()
if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
  GIT_CRYPT_FLAGS=(-c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat)
fi
```

## Step 3: Compute Project Name and Index

```bash
PROJECT="$(basename "$(git rev-parse --show-toplevel)")"
PARENT="$(dirname "$(git rev-parse --show-toplevel)")"

# Find next available index
# Scan parent directory for {PROJECT}-{AGENT}-N pattern
NEXT_INDEX=1
for dir in "${PARENT}/${PROJECT}-${AGENT}"-*/; do
  if [[ -d "$dir" ]]; then
    N="${dir##*-}"
    N="${N%/}"
    if [[ "$N" =~ ^[0-9]+$ ]] && (( N >= NEXT_INDEX )); then
      NEXT_INDEX=$((N + 1))
    fi
  fi
done

WORKTREE_PATH="${PARENT}/${PROJECT}-${AGENT}-${NEXT_INDEX}"
```

## Step 3.5: Lock Acquisition

Use `mkdir` for atomic lock (cross-platform: Linux, macOS, WSL).

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
LOCKDIR="${GIT_COMMON}/ai-worktree-spawn.lock"
MAX_RETRIES=3
LOCK_TIMEOUT=10  # seconds

acquire_lock() {
  local retries=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    # Check for stale lock
    if [[ -f "$LOCKDIR/pid" ]]; then
      local lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCKDIR/pid" 2>/dev/null || stat -f %m "$LOCKDIR/pid" 2>/dev/null) ))
      if (( lock_age > LOCK_TIMEOUT )); then
        echo "Warning: Stale lock detected (age ${lock_age}s), removing"
        rm -rf "$LOCKDIR"
        continue
      fi
    fi
    retries=$((retries + 1))
    if (( retries >= MAX_RETRIES )); then
      echo "Error: Failed to acquire lock after $MAX_RETRIES retries"
      exit 2
    fi
    echo "Waiting for lock... retry $retries/$MAX_RETRIES"
    sleep 1
  done
  echo $$ > "$LOCKDIR/pid"
}

release_lock() {
  rm -rf "$LOCKDIR"
}

# Usage: wrap index computation + worktree creation
acquire_lock
trap release_lock EXIT
# ... Steps 3 through 6 run here ...
release_lock
trap - EXIT
```

## Step 4: Determine Branch Name

```bash
normalize_slug() {
  # Lowercase, replace non-alnum with hyphens, trim, max 30 chars
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30
}

if [[ -n "${EXPLICIT_BRANCH:-}" ]]; then
  BRANCH="$EXPLICIT_BRANCH"
elif [[ -n "${TASK_SLUG:-}" ]]; then
  SLUG="$(normalize_slug "$TASK_SLUG")"
  BRANCH="wt/${AGENT}/${NEXT_INDEX}-${SLUG}"
else
  BRANCH="wt/${AGENT}/${NEXT_INDEX}"
fi
```

## Step 5: Determine Base Ref

```bash
resolve_base_ref() {
  local explicit_base="${1:-}"

  # Priority 1: explicit --base argument
  if [[ -n "$explicit_base" ]]; then
    if git rev-parse --verify --quiet "$explicit_base" >/dev/null 2>&1; then
      echo "$explicit_base"
      return
    fi
    echo "Error: Base ref not found: $explicit_base" >&2
    exit 1
  fi

  # Priority 2: origin/main
  if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
    echo "origin/main"; return
  fi

  # Priority 3: main or master
  if git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
    echo "main"; return
  fi
  if git rev-parse --verify --quiet "master" >/dev/null 2>&1; then
    echo "master"; return
  fi

  # Priority 4: current HEAD
  echo "HEAD"
}

BASE_REF="$(resolve_base_ref "${BASE_OVERRIDE:-}")"
```

## Step 6: Create Worktree

```bash
# Use GIT_CRYPT_FLAGS from Step 1.5 (empty array if no git-crypt)
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    # Existing branch -- no -b flag
    git "${GIT_CRYPT_FLAGS[@]}" worktree add "${WORKTREE_PATH}" "${BRANCH}"
else
    # New branch -- create with -b
    git "${GIT_CRYPT_FLAGS[@]}" worktree add -b "${BRANCH}" "${WORKTREE_PATH}" "${BASE_REF}"
fi

# If git-crypt is active, disable filters in the new worktree permanently.
# Encrypted files (.env, .secrets) stay as binary -- this is intentional.
# The worktree is for code work; secrets are not needed.
if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required false
    # Re-checkout so worktree-local config takes effect cleanly
    git -C "${WORKTREE_PATH}" checkout -- . 2>/dev/null
fi
```

## Step 7: Log the Creation

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] SPAWN project=${PROJECT} agent=${AGENT} index=${NEXT_INDEX} path=${WORKTREE_PATH} branch=${BRANCH} base=${BASE_REF}" \
  >> "${GIT_COMMON}/ai-worktree-spawn.log"
```
