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

## Step 3: Compute Project Name and Index

```bash
PROJECT="$(basename "$(git rev-parse --show-toplevel)")"
AGENT="<detected-agent>"
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

## Step 6: Create Worktree

```bash
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    # Existing branch -- no -b flag
    git worktree add "${WORKTREE_PATH}" "${BRANCH}"
else
    # New branch -- create with -b
    git worktree add -b "${BRANCH}" "${WORKTREE_PATH}" "${BASE_REF}"
fi
```

## Step 7: Log the Creation

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
echo "[$(date -Iseconds)] SPAWN project=${PROJECT} agent=${AGENT} index=${NEXT_INDEX} path=${WORKTREE_PATH} branch=${BRANCH} base=${BASE_REF}" \
  >> "${GIT_COMMON}/ai-worktree-spawn.log"
```
