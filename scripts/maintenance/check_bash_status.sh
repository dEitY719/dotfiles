#!/usr/bin/env bash
# check_bash_status.sh
# Inspect .bash files one by one in clean shells with tracing.

set -Eeuo pipefail

show_help() {
  cat <<'EOF'
Usage: ./check_bash_status.sh [ROOT_DIR(default: ./bash)] [--mode isolated|chain] [--logdir ./bash_check_logs]

Options:
  ROOT_DIR        Directory to search for .bash files (default: ./bash)
  --mode MODE     Run mode: isolated (default) or chain
                  isolated : each file in a fresh shell
                  chain    : all files sourced in one shell sequentially
  --logdir DIR    Directory to store logs (default: ./bash_check_logs)
  --help          Show this help message

Examples:
  ./check_bash_status.sh
  ./check_bash_status.sh ./bash --mode isolated
  ./check_bash_status.sh ./bash --mode chain --logdir ./logs
EOF
}

# defaults
ROOT_DIR="./bash"
MODE="isolated"
LOG_DIR="./bash_check_logs"

# --- parse args: options first, then positional ROOT_DIR (first non-option) ---
ROOT_DIR_SET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --mode)
      [[ $# -ge 2 ]] || { echo "[ERR] --mode requires a value" >&2; exit 2; }
      MODE="$2"; shift 2
      ;;
    --logdir)
      [[ $# -ge 2 ]] || { echo "[ERR] --logdir requires a value" >&2; exit 2; }
      LOG_DIR="$2"; shift 2
      ;;
    --) # end of options
      shift
      break
      ;;
    -*)
      echo "[ERR] unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ $ROOT_DIR_SET -eq 0 ]]; then
        ROOT_DIR="$1"
        ROOT_DIR_SET=1
        shift
      else
        echo "[ERR] multiple ROOT_DIR values supplied (already have '$ROOT_DIR', extra '$1')" >&2
        exit 2
      fi
      ;;
  esac
done

mkdir -p "$LOG_DIR"

# colors
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; NORMAL="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"
else
  BOLD=""; NORMAL=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

# sanity checks
if [[ ! -d "$ROOT_DIR" ]]; then
  echo "${RED}[ERR]${NORMAL} ROOT_DIR does not exist or is not a directory: ${ROOT_DIR}" >&2
  exit 2
fi

# collect files
mapfile -t FILES < <(find "$ROOT_DIR" -type f -name '*.bash' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "${YELLOW}[WARN]${NORMAL} No .bash files under ${ROOT_DIR}"
  exit 0
fi

echo "${BOLD}Checking .bash files under: ${ROOT_DIR}${NORMAL}"
echo "Mode: ${BOLD}${MODE}${NORMAL}"
echo "Log dir: ${BOLD}${LOG_DIR}${NORMAL}"
echo

run_isolated() {
  for f in "${FILES[@]}"; do
    [[ -n "${f:-}" ]] || continue

    rel="${f#"$ROOT_DIR"/}"
    [[ "$rel" == "$f" ]] && rel="$(realpath --relative-to="$ROOT_DIR" "$f" 2>/dev/null || echo "$f")"
    log="${LOG_DIR}/isolated_${rel//\//_}.log"

    echo "${BLUE}[*]${NORMAL} ${rel}"

    tmp_script="$(mktemp)"
{
  cat <<'EOS'
set -Eeuo pipefail
PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}() '
export BASH_XTRACEFD=3
set -x
trap 'code=$?; echo "ERR($code) at ${BASH_SOURCE[0]}:${LINENO} -> ${BASH_COMMAND}" >&2' ERR
EOS
  printf 'exec 3> "%s"\n' "$log"

  printf 'bash -n "%s"\n' "$f"
  printf 'source "%s"\n' "$f"

  # 👇 성공 메시지를 stdout과 fd3(xtrace 로그) 둘 다에 남김
  printf 'echo ">>> LOAD OK: %s"\n' "$f"
  printf 'echo "체크한 결과, 정상입니다. (%s)" >&3\n' "$f"
} > "$tmp_script"


    # 깨끗한 셸에서 실행 (여기서는 3> 리다이렉션 붙이지 않음)
    if ! bash --noprofile --norc "$tmp_script"; then
      echo "    ${RED}[FAIL]${NORMAL} ${rel}"
      echo "    Trace: ${log}"
      echo
      tail -n 30 "$log" | sed 's/^/    /'
      rm -f "$tmp_script"
      exit 1
    else
      echo "    ${GREEN}[OK]${NORMAL} ${rel}  (trace: ${log})"
    fi
    rm -f "$tmp_script"
  done
}

run_chain() {
  log="${LOG_DIR}/chain.log"
  tmp_script="$(mktemp)"
  {
    cat <<'EOS'
set -Eeuo pipefail
PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}() '
export BASH_XTRACEFD=3
set -x
trap 'code=$?; echo "ERR($code) at ${BASH_SOURCE[0]}:${LINENO} -> ${BASH_COMMAND}" >&2' ERR
EOS
    # chain 전체의 xtrace를 chain.log에 기록
    printf 'exec 3> "%s"\n' "$log"

    for f in "${FILES[@]}"; do
      printf 'echo "--- SOURCE: %s"\n' "$f"
      printf 'bash -n "%s"\n' "$f"
      printf 'source "%s"\n' "$f"
    done
    printf 'echo ">>> LOAD OK: chained %d files"\n' "${#FILES[@]}"
  } > "$tmp_script"

  if ! bash --noprofile --norc "$tmp_script"; then
    echo "${RED}[FAIL]${NORMAL} chain mode"
    echo "Trace: ${log}"
    echo
    tail -n 80 "$log" | sed 's/^/    /'
    rm -f "$tmp_script"
    exit 1
  else
    echo "${GREEN}[OK]${NORMAL} chain mode (trace: ${log})"
  fi
  rm -f "$tmp_script"
  # 헤더/exec 3>.../루프는 그대로 유지하고, 맨 끝 메시지 2줄만 교체
  printf 'echo ">>> LOAD OK: chained %d files"\n' "${#FILES[@]}"
  printf 'echo "체크한 결과, 정상입니다. (chain, %d files)" >&3\n' "${#FILES[@]}"
}

case "$MODE" in
  isolated) run_isolated ;;
  chain) run_chain ;;
  *) echo "[ERR] invalid --mode: $MODE" >&2; exit 2 ;;
esac

echo
echo "${GREEN}${BOLD}All good!${NORMAL}"
