#!/bin/bash
# shell-common/tools/custom/mirror-pages-activate.sh
# Activates GitHub Pages on the GHE origin repo and replaces upstream
# github.io Pages URLs in README.md with the GHE Pages URL.
# Run from inside a mirrored repo (origin=GHE, upstream=github.com).
# Usage: mirror-pages-activate [--dry-run]

set -euo pipefail

# --- Resolve SHELL_COMMON relative to this script's real path ---
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_SCRIPT_DIR="$(dirname "${_SCRIPT_PATH}")"
SHELL_COMMON="${_SCRIPT_DIR%/tools/custom}"
export SHELL_COMMON

# --- Load ux_lib; fall back to plain output if not available ---
if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
	# shellcheck source=/dev/null
	source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
else
	ux_header() { printf '=== %s ===\n' "$*"; }
	ux_success() { printf '[OK] %s\n' "$*"; }
	ux_error() { printf '[ERROR] %s\n' "$*" >&2; }
	ux_info() { printf '  %s\n' "$*"; }
	ux_step() { printf '-- Step %s: %s\n' "$1" "$2"; }
fi

main() {
	# --- Parse arguments ---
	local _DRY_RUN=0
	for _arg in "$@"; do
		case "${_arg}" in
		--dry-run)
			_DRY_RUN=1
			;;
		-h | --help)
			printf 'Usage: mirror-pages-activate [--dry-run]\n\n'
			printf '  Activates GitHub Pages on the GHE origin repo and replaces\n'
			printf '  upstream github.io URLs in README.md with the GHE Pages URL.\n\n'
			printf '  Must be run from inside a mirrored repo:\n'
			printf '    origin   = GHE mirror  (https://<ghe-host>/owner/repo)\n'
			printf '    upstream = github.com source\n\n'
			printf '  Pages source defaults to: branch=main, path=/docs\n\n'
			printf 'Options:\n'
			printf '  --dry-run  Preview actions without making changes\n'
			exit 0
			;;
		*)
			ux_error "Unknown option: ${_arg}"
			exit 1
			;;
		esac
	done

	# --- Preconditions ---
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		ux_error "Not inside a git repository."
		exit 1
	fi

	local _origin_url _upstream_url
	_origin_url=$(git remote get-url origin 2>/dev/null || true)
	_upstream_url=$(git remote get-url upstream 2>/dev/null || true)

	if [ -z "${_origin_url}" ]; then
		ux_error "No 'origin' remote found. Expected a GHE mirror URL."
		exit 1
	fi
	if [ -z "${_upstream_url}" ]; then
		ux_error "No 'upstream' remote found. Expected a github.com source URL."
		exit 1
	fi

	# --- Parse origin URL: https://<ghe-host>/<owner>/<repo>[.git] ---
	local _o _ghe_host _origin_owner _repo_name
	_o="${_origin_url%.git}"
	_o="${_o#*://}"
	_ghe_host="${_o%%/*}"
	_ghe_host="${_ghe_host%%:*}"
	_o="${_o#*/}"
	_origin_owner="${_o%%/*}"
	_repo_name="${_o##*/}"

	# --- Parse upstream URL: https://github.com/<owner>/<repo>[.git] ---
	local _u _upstream_owner
	_u="${_upstream_url%.git}"
	_u="${_u#*://}"
	_u="${_u#*/}"
	_upstream_owner="${_u%%/*}"

	# --- Validate ---
	if [ "${_ghe_host}" = "github.com" ]; then
		ux_error "origin points to github.com — expected a GHE host. Are the remotes swapped?"
		exit 1
	fi

	# --- Derive Pages URL components ---
	# GitHub Pages hostnames are always lowercase, so normalize the upstream
	# owner before building the github.io base (#955 — dEitY719 vs deity719).
	local _upstream_pages_base _origin_pages_base _origin_pages_url _upstream_owner_lc
	_upstream_owner_lc=$(printf '%s' "${_upstream_owner}" | tr '[:upper:]' '[:lower:]')
	_upstream_pages_base="${_upstream_owner_lc}.github.io/${_repo_name}"
	_origin_pages_base="${_ghe_host}/pages/${_origin_owner}/${_repo_name}"
	_origin_pages_url="https://${_origin_pages_base}"

	# --- Header ---
	ux_header "mirror-pages-activate"
	ux_info "GHE host       : ${_ghe_host}"
	ux_info "Origin         : ${_origin_owner}/${_repo_name}"
	ux_info "Upstream owner : ${_upstream_owner}"
	ux_info "Upstream Pages : https://${_upstream_pages_base}"
	ux_info "Origin Pages   : ${_origin_pages_url}"
	[ "${_DRY_RUN}" -eq 1 ] && ux_info "(dry-run — no changes)"
	printf '\n'

	# --- Step 1: Activate GitHub Pages ---
	ux_step 1 "GitHub Pages activation"

	# When Pages is inactive the API returns 404 and `gh` exits non-zero, so
	# stdout is empty. Don't substitute a sentinel — an empty string is the
	# unambiguous "not active" signal (#955).
	local _pages_status
	_pages_status=$(gh api --hostname "${_ghe_host}" \
		"repos/${_origin_owner}/${_repo_name}/pages" \
		--jq '.status' 2>/dev/null) || _pages_status=""

	if [ -n "${_pages_status}" ]; then
		ux_info "Pages already active (status: ${_pages_status}) — skip"
	else
		if [ "${_DRY_RUN}" -eq 1 ]; then
			ux_info "[dry-run] Would POST repos/${_origin_owner}/${_repo_name}/pages"
			ux_info "[dry-run]   source[branch]=main  source[path]=/docs"
		else
			# GHE 3.17's Pages API requires a JSON body and rejects the
			# form-urlencoded payload produced by `gh api -F`, so send JSON
			# via --input. Capture stdout+stderr instead of discarding them
			# so a real API rejection is surfaced rather than swallowed (#957).
			local _pages_err _pages_rc=0
			_pages_err=$(printf '{"source":{"branch":"main","path":"/docs"}}' |
				gh api --hostname "${_ghe_host}" \
					"repos/${_origin_owner}/${_repo_name}/pages" \
					--method POST \
					--input - 2>&1) || _pages_rc=$?

			if [ "${_pages_rc}" -eq 0 ]; then
				ux_success "Pages activated (branch=main, path=/docs)"
			else
				ux_error "Pages activation failed (exit ${_pages_rc})."
				[ -n "${_pages_err}" ] && ux_info "API response: ${_pages_err}"
				ux_info "Verify: gh auth status --hostname ${_ghe_host}"
				exit 1
			fi
		fi
	fi

	# --- Step 2: Replace upstream Pages URLs in README.md ---
	ux_step 2 "README.md URL replacement"

	local _count
	if [ ! -f README.md ]; then
		ux_info "README.md not found — skip"
	else
		_count=$(grep -c "${_upstream_pages_base}" README.md 2>/dev/null) || _count=0
		if [ "${_count}" -eq 0 ]; then
			ux_info "No upstream Pages URLs in README.md — nothing to do"
		elif [ "${_DRY_RUN}" -eq 1 ]; then
			ux_info "[dry-run] Would replace ${_count} occurrence(s) of '${_upstream_pages_base}'"
			ux_info "[dry-run]   -> '${_origin_pages_base}'"
			ux_info "[dry-run] Matching lines:"
			grep -n "${_upstream_pages_base}" README.md | while IFS= read -r _line; do
				ux_info "  ${_line}"
			done
		else
			local _tmp
			_tmp=$(mktemp "${TMPDIR:-/tmp}/mirror-pages.XXXXXX")
			sed "s|${_upstream_pages_base}|${_origin_pages_base}|g" README.md >"${_tmp}"
			mv "${_tmp}" README.md
			ux_success "Replaced ${_count} occurrence(s) in README.md"
		fi
	fi

	printf '\n'
	ux_success "Done."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
	main "$@"
fi
