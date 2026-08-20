#!/bin/bash
# hermes/setup.sh: Hermes Agent install + config activation
#
# PURPOSE: Make a fresh machine's Hermes Agent match this repo — symlink the
#          tracked config, install the CLI, wire up a custom OpenAI-compatible
#          LLM endpoint, and (optionally) prepare the browser automation tool
#          for a TLS-intercepting network.
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
#       Endpoint credentials declared in hermes/llm_endpoint.local.sh
#       (gitignored — copy hermes/llm_endpoint.local.example to create it)
#
# Failure policy: Part 1 (config symlink) hard-fails — a missing source means a
# dangling link and hermes silently reverting to its defaults. Parts 2-5
# soft-fail: they reach the network (installer, npm registry) or depend on
# host-specific state (a certificate path, certutil) that this script cannot
# fix, and everything they provide degrades gracefully — no CLI means the help
# text still tells you how to install it, no endpoint config means hermes falls
# back to its own provider defaults, no browser tool means the agent loses one
# capability. Never abort the parent setup.sh — which runs under `set -e` —
# over any of it: warn and move on.
#
# Optional inputs (all unset by default; each unset one skips its Part):
#   HERMES_AGENT_BROWSER_DIR    — where agent-browser's package.json lives
#   HERMES_BROWSER_FULL_INSTALL — 1 installs the desktop (Electron) workspace too
#   HERMES_CORP_CA_CERT         — root CA to import into Chromium's NSS store
# Opt out of the install halves with HERMES_SKIP_INSTALL=1 / HERMES_SKIP_BROWSER=1.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/hermes}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

HERMES_CONFIG_SRC="${_SCRIPT_DIR}/config.yaml"
HERMES_CONFIG_DIR="${HOME}/.hermes"
HERMES_CONFIG_LINK="${HERMES_CONFIG_DIR}/config.yaml"
HERMES_ENDPOINT_LOCAL="${_SCRIPT_DIR}/llm_endpoint.local.sh"
HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"

ux_header "Hermes Agent Setup"

# ============================================================================
# Part 1: config symlink (hard-fail)
# ============================================================================

# The source must exist; without it the symlink would dangle and hermes would
# silently fall back to its built-in defaults.
if [ ! -f "${HERMES_CONFIG_SRC}" ]; then
	ux_error "Source config not found: ${HERMES_CONFIG_SRC}"
	exit 1
fi

# hermes creates this directory itself on first run, but setup.sh may run first.
if [ ! -d "${HERMES_CONFIG_DIR}" ]; then
	mkdir -p "${HERMES_CONFIG_DIR}" || { ux_error "Could not create: ${HERMES_CONFIG_DIR}"; exit 1; }
	ux_success "Created: ~/.hermes"
fi

# A function so the "already correct" case returns early instead of nesting the
# rewrite branch. Body matches herdr/setup.sh's _herdr_link_config.
_hermes_link_config() {
	if [ -L "${HERMES_CONFIG_LINK}" ]; then
		local current_target
		current_target=$(readlink "${HERMES_CONFIG_LINK}")
		if [ "${current_target}" = "${HERMES_CONFIG_SRC}" ]; then
			ux_success "Symlink already correct: ~/.hermes/config.yaml → ${HERMES_CONFIG_SRC}"
			return 0
		fi
		ux_info "Updating symlink (was: ${current_target})"
		rm "${HERMES_CONFIG_LINK}" || { ux_error "Could not remove stale symlink: ${HERMES_CONFIG_LINK}"; exit 1; }
	elif [ -e "${HERMES_CONFIG_LINK}" ]; then
		local backup="${HERMES_CONFIG_LINK}.backup"
		rm -f "${backup}"
		ux_info "Backing up existing file: ${backup}"
		mv "${HERMES_CONFIG_LINK}" "${backup}" || { ux_error "Could not back up: ${HERMES_CONFIG_LINK}"; exit 1; }
	fi

	ln -s "${HERMES_CONFIG_SRC}" "${HERMES_CONFIG_LINK}" || { ux_error "Could not create symlink: ${HERMES_CONFIG_LINK}"; exit 1; }
	ux_success "Created: ~/.hermes/config.yaml → ${HERMES_CONFIG_SRC}"
}

# `hermes config set` (Part 3) rewrites whatever ~/.hermes/config.yaml points
# at. Left as a symlink, that write lands on the tracked hermes/config.yaml —
# the exact leak F-2/NF-1 forbid. Detach the link into a real local copy
# before any secret write; the next run's _hermes_link_config backs that copy
# up and re-links from the repo, so tracked defaults still propagate.
_hermes_materialize_config() {
	if [ -L "${HERMES_CONFIG_LINK}" ]; then
		local resolved
		resolved=$(readlink "${HERMES_CONFIG_LINK}")
		rm "${HERMES_CONFIG_LINK}" || { ux_error "Could not detach symlink: ${HERMES_CONFIG_LINK}"; return 1; }
		cp "${resolved}" "${HERMES_CONFIG_LINK}" || { ux_error "Could not materialize config: ${HERMES_CONFIG_LINK}"; return 1; }
	fi
	return 0
}

_hermes_link_config

# ============================================================================
# Part 2: CLI install (soft-fail, idempotent)
# ============================================================================

_hermes_install_cli() {
	if [ "${HERMES_SKIP_INSTALL:-0}" = "1" ]; then
		ux_info "Hermes CLI install skipped (HERMES_SKIP_INSTALL=1)"
		return 0
	fi

	# `hermes --version` is the idempotence check the acceptance criteria name.
	if command -v hermes >/dev/null 2>&1; then
		ux_success "hermes already installed: $(hermes --version 2>&1 | head -1)"
		return 0
	fi

	if ! command -v curl >/dev/null 2>&1; then
		ux_warning "curl not on PATH — Hermes CLI install skipped"
		ux_bullet "Install curl, then re-run: ./hermes/setup.sh"
		return 0
	fi

	ux_section "Hermes CLI"
	ux_info "installing from ${HERMES_INSTALL_URL}"

	# Piping the installer to sh is upstream's documented path. It is also the
	# one step that reaches the public internet, so a proxied/offline machine
	# fails here — say what to retry and move on.
	if curl -fsSL "${HERMES_INSTALL_URL}" | sh; then
		if command -v hermes >/dev/null 2>&1; then
			ux_success "installed: $(hermes --version 2>&1 | head -1)"
		else
			# The installer usually drops the binary in a dir this shell's PATH
			# picked up before the install ran; a new shell resolves it.
			ux_success "installer finished — open a new shell so PATH picks up hermes"
		fi
	else
		ux_warning "Hermes CLI install failed (network or proxy is the usual cause)"
		ux_bullet "Retry: curl -fsSL ${HERMES_INSTALL_URL} | sh"
		ux_bullet "Details: hermes-help install"
	fi

	return 0
}

_hermes_install_cli

# ============================================================================
# Part 3: custom LLM endpoint (soft-fail, optional)
# ============================================================================

# Why `hermes config set` and not the tracked config.yaml: the api_key must
# never land in a git-tracked file (F-2). And why config.yaml at all rather
# than ~/.hermes/.env — hermes host-gates OPENAI_API_KEY to openai.com /
# openai.azure.com, so a .env key is silently dropped for a custom base_url and
# the request comes back 401. See hermes-help pitfalls.
_hermes_configure_endpoint() {
	if [ ! -f "${HERMES_ENDPOINT_LOCAL}" ]; then
		ux_info "No custom LLM endpoint configured — skipping"
		ux_bullet "To wire one up: cp hermes/llm_endpoint.local.example hermes/llm_endpoint.local.sh"
		ux_bullet "Fill in HERMES_LLM_BASE_URL / HERMES_LLM_API_KEY, then re-run ./hermes/setup.sh"
		return 0
	fi

	# shellcheck source=/dev/null
	. "${HERMES_ENDPOINT_LOCAL}" || { ux_warning "Could not source: ${HERMES_ENDPOINT_LOCAL}"; return 0; }

	if [ -z "${HERMES_LLM_BASE_URL:-}" ] && [ -z "${HERMES_LLM_API_KEY:-}" ]; then
		ux_warning "${HERMES_ENDPOINT_LOCAL} sets neither HERMES_LLM_BASE_URL nor HERMES_LLM_API_KEY — skipping"
		return 0
	fi

	if ! command -v hermes >/dev/null 2>&1; then
		ux_info "hermes not on PATH — endpoint configuration skipped"
		ux_bullet "Install hermes first: hermes-help install"
		return 0
	fi

	_hermes_materialize_config || { ux_warning "Could not detach ~/.hermes/config.yaml from the repo symlink — skipping endpoint write to avoid leaking a secret into a tracked file"; return 0; }

	ux_section "Custom LLM endpoint"

	if [ -n "${HERMES_LLM_BASE_URL:-}" ]; then
		if hermes config set model.base_url "${HERMES_LLM_BASE_URL}" >/dev/null 2>&1; then
			ux_success "set model.base_url (${HERMES_LLM_BASE_URL})"
		else
			ux_warning "Could not set model.base_url — run manually: hermes config set model.base_url <url>"
		fi
	fi

	# The value is never echoed — only whether the write landed.
	if [ -n "${HERMES_LLM_API_KEY:-}" ]; then
		if hermes config set model.api_key "${HERMES_LLM_API_KEY}" >/dev/null 2>&1; then
			ux_success "set model.api_key (value not printed)"
		else
			ux_warning "Could not set model.api_key — run manually: hermes config set model.api_key <key>"
		fi
	fi

	ux_bullet "Verify: hermes doctor"
	return 0
}

_hermes_configure_endpoint

# ============================================================================
# Part 4: agent-browser (soft-fail, optional)
# ============================================================================

# agent-browser is a root-package.json dependency that happens to sit in a
# workspace tree shared with the Electron desktop app. `--workspaces=false`
# installs the root only, which is all the CLI needs (pitfall 2).
#
# The install location is not fixed by this repo — it depends on how the
# upstream installer laid things out on this host. Rather than hardcode a path
# that may not exist, probe a couple of likely ones and otherwise ask the user.
_hermes_find_browser_dir() {
	local candidate
	for candidate in "${HOME}/.hermes" "${HOME}/.local/share/hermes"; do
		if [ -f "${candidate}/package.json" ]; then
			printf '%s' "${candidate}"
			return 0
		fi
	done
	return 1
}

_hermes_install_browser() {
	if [ "${HERMES_SKIP_BROWSER:-0}" = "1" ]; then
		ux_info "agent-browser install skipped (HERMES_SKIP_BROWSER=1)"
		return 0
	fi

	local browser_dir="${HERMES_AGENT_BROWSER_DIR:-}"

	if [ -n "${browser_dir}" ]; then
		if [ ! -f "${browser_dir}/package.json" ]; then
			ux_warning "HERMES_AGENT_BROWSER_DIR has no package.json: ${browser_dir} — skipping"
			return 0
		fi
	else
		browser_dir=$(_hermes_find_browser_dir) || {
			ux_info "agent-browser install location not found — skipping"
			ux_bullet "Point at it explicitly: HERMES_AGENT_BROWSER_DIR=<dir with package.json> ./hermes/setup.sh"
			ux_bullet "Or install by hand — see: hermes-help install"
			return 0
		}
	fi

	if ! command -v npm >/dev/null 2>&1; then
		ux_warning "npm not on PATH — agent-browser install skipped"
		return 0
	fi

	ux_section "agent-browser"

	local npm_flag="--workspaces=false"
	local mode="root only (--workspaces=false)"
	if [ "${HERMES_BROWSER_FULL_INSTALL:-0}" = "1" ]; then
		npm_flag=""
		mode="full (desktop workspace included)"
	fi

	ux_info "installing in ${browser_dir} — ${mode}"
	if (cd "${browser_dir}" && npm install ${npm_flag}); then
		ux_success "agent-browser dependencies installed (${mode})"
		if [ -n "${npm_flag}" ]; then
			ux_bullet "Need the Electron desktop app too? HERMES_BROWSER_FULL_INSTALL=1 ./hermes/setup.sh"
		fi
	else
		ux_warning "npm install failed in ${browser_dir}"
		ux_bullet "Retry: cd ${browser_dir} && npm install ${npm_flag}"
	fi

	return 0
}

_hermes_install_browser

# ============================================================================
# Part 5: root CA import for Chromium's NSS store (soft-fail, optional)
# ============================================================================

# Chromium — which agent-browser drives — reads its own NSS database, not the
# system CA bundle. Behind a TLS-intercepting proxy that makes every navigation
# fail with an SSL error while curl/pip/uv keep working (pitfall 3).
#
# Fallback source: a machine that already configured a corporate CA has the
# path in shell-common/env/security.local.sh as $CA_CERT. Read it in a subshell
# so that file's other exports (proxy vars, NODE_EXTRA_CA_CERTS) do not leak
# into this setup run.
_hermes_resolve_ca_cert() {
	if [ -n "${HERMES_CORP_CA_CERT:-}" ]; then
		printf '%s' "${HERMES_CORP_CA_CERT}"
		return 0
	fi

	local security_local="${SHELL_COMMON}/env/security.local.sh"
	[ -f "${security_local}" ] || return 1

	local from_security
	# shellcheck source=/dev/null
	from_security=$(DOTFILES_FORCE_INIT=1 sh -c '. "$1" >/dev/null 2>&1; printf "%s" "${CA_CERT:-}"' _ "${security_local}" 2>/dev/null)
	[ -n "${from_security}" ] || return 1

	printf '%s' "${from_security}"
	return 0
}

_hermes_import_ca() {
	local cert_path
	cert_path=$(_hermes_resolve_ca_cert) || {
		# The common case on a normal network: nothing to do, and no sudo
		# prompt (F-4).
		return 0
	}

	ux_section "Chromium NSS root CA"

	if [ ! -f "${cert_path}" ]; then
		ux_warning "CA certificate not found: ${cert_path} — skipping NSS import"
		return 0
	fi

	if ! command -v certutil >/dev/null 2>&1; then
		ux_warning "certutil not found — agent-browser may fail with SSL errors behind a TLS-intercepting proxy"
		ux_bullet "Install it: sudo apt install libnss3-tools   (then re-run ./hermes/setup.sh)"
		return 0
	fi

	mkdir -p "${HOME}/.pki/nssdb" || { ux_warning "Could not create ~/.pki/nssdb — skipping NSS import"; return 0; }

	# -A on an existing nickname replaces it, so re-running is idempotent.
	if certutil -d "sql:${HOME}/.pki/nssdb" -A -t "C,," -n "corp-root-ca" -i "${cert_path}" >/dev/null 2>&1; then
		ux_success "imported ${cert_path} into ~/.pki/nssdb as 'corp-root-ca'"
		ux_bullet "Verify: certutil -d sql:\$HOME/.pki/nssdb -L"
		ux_bullet "snap Chromium keeps a separate DB — see: hermes-help pitfalls"
	else
		ux_warning "certutil import failed for ${cert_path}"
		ux_bullet "Retry: certutil -d sql:\$HOME/.pki/nssdb -A -t \"C,,\" -n corp-root-ca -i ${cert_path}"
	fi

	return 0
}

_hermes_import_ca

ux_info "Details and pitfalls: hermes-help"

# Install failures are warnings, never fatal — pin the status so the parent's
# `set -e` cannot trip over Parts 2-5. See the header comment.
exit 0
