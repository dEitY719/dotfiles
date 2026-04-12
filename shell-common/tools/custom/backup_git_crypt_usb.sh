#!/bin/bash

# shell-common/tools/custom/backup_git_crypt_usb.sh
#
# PURPOSE: Create a USB recovery backup for git-crypt bootstrap on a new PC.
# WHEN TO RUN: Once when you have a working unlocked dotfiles repo. Periodically
#              after key rotation or after adding new SSH keys.
#
# OUTPUT: 4 files on the USB under dotfiles-recovery/:
#   01-gpg-privkey-<KEYID>.asc.gpg   (A) GPG private key, symmetric-encrypted
#   02-git-crypt-master.key.gpg      (B) git-crypt master key, symmetric-encrypted
#   03-ssh-<hostname>.tar.gpg        (C) SSH keys archive, symmetric-encrypted
#   04-recovery-metadata.txt         (D) plaintext operations manual (no secrets)
#
# The on-screen SUMMARY block at the end is also written into (D) so the user
# may transcribe it to a notebook / Obsidian / OneNote, or simply read it off
# the USB itself during future recovery.

set -e

# Initialize common tools environment (loads ux_lib, sets DOTFILES_ROOT, etc.)
source "$(dirname "$0")/init.sh" || exit 1

# ----------------------------------------------------------------------------
# Secure workspace: all plaintext intermediates live here, shredded on exit.
# ----------------------------------------------------------------------------
WORKDIR="$(mktemp -d -t gc-usb-backup.XXXXXX)"
chmod 700 "$WORKDIR"

cleanup() {
    if [[ -d "$WORKDIR" ]]; then
        # Shred every file recursively before removing the dir.
        find "$WORKDIR" -type f -exec shred -u {} \; 2>/dev/null || true
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
die() {
    ux_error "$*"
    exit 1
}

ask_path() {
    # ux_input "<prompt>" "<default>" — returns user input via stdout.
    local prompt="$1"
    local default="${2:-}"
    ux_input "$prompt" "$default"
}

file_size_h() {
    local f="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")"
    else
        stat -c%s "$f" 2>/dev/null || stat -f%z "$f"
    fi
}

sha256_of() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

# ----------------------------------------------------------------------------
# Step 0: Preflight
# ----------------------------------------------------------------------------
preflight() {
    ux_step "0/5" "Preflight checks"

    local missing=()
    for tool in gpg git-crypt tar sha256sum shred stat awk; do
        have_command "$tool" || missing+=("$tool")
    done
    if ((${#missing[@]} > 0)); then
        die "Missing required tools: ${missing[*]}"
    fi
    ux_bullet "required tools present"

    # Must be run from within dotfiles repo (uses DOTFILES_ROOT from init.sh)
    cd "$DOTFILES_ROOT" || die "cannot cd to \$DOTFILES_ROOT ($DOTFILES_ROOT)"
    [[ -d .git && -d .git-crypt ]] || die "not a git-crypt-enabled repo at $DOTFILES_ROOT"
    ux_bullet "dotfiles repo: $DOTFILES_ROOT"

    # git-crypt must be unlocked — detect by looking at .env content type.
    if [[ -f .env ]] && ! file .env | grep -q "text"; then
        die ".env is still encrypted — run 'git-crypt unlock' first, then re-run this script."
    fi
    ux_bullet "git-crypt is unlocked"

    # GPG keyring must have a secret key matching a key in .git-crypt/keys/
    local key_id="" key_file=""
    for f in .git-crypt/keys/default/0/*.gpg; do
        if [[ -f "$f" ]]; then
            key_file="$f"
            break
        fi
    done
    [[ -n "$key_file" ]] || die "cannot detect git-crypt GPG key id from .git-crypt/keys/default/0/"
    key_id="$(basename "$key_file" .gpg)"
    local short_id="${key_id: -16}"
    if ! gpg --list-secret-keys --keyid-format=long "$short_id" >/dev/null 2>&1; then
        die "GPG secret key $short_id not found in your keyring."
    fi
    ux_bullet "GPG secret key found: $short_id"

    echo ""
    # Export for later steps.
    GPG_FPR="$key_id"
    GPG_SHORT_ID="$short_id"
}

# ----------------------------------------------------------------------------
# Step 1: Ask the 3 questions up front so the user can walk away afterwards.
# ----------------------------------------------------------------------------
ask_inputs() {
    ux_step "1/5" "Questions (we will ask these up-front)"

    USB_ROOT="$(ask_path "USB mount path (e.g., /mnt/usb or /media/$USER/USB)" "")"
    [[ -n "$USB_ROOT" ]] || die "USB path is required"
    [[ -d "$USB_ROOT" ]] || die "USB path does not exist: $USB_ROOT"
    [[ -w "$USB_ROOT" ]] || die "USB path is not writable: $USB_ROOT"

    # Warn if the path looks like a non-removable location.
    case "$USB_ROOT" in
    /tmp* | "$HOME" | "$HOME"/* | /var* | /opt*)
        ux_warning "path '$USB_ROOT' does not look like a removable drive"
        ux_confirm "Proceed anyway?" "n" || die "aborted by user"
        ;;
    esac

    USB_DIR="${USB_ROOT%/}/dotfiles-recovery"
    if [[ -d "$USB_DIR" ]]; then
        ux_warning "$USB_DIR already exists — files will be overwritten"
        ux_confirm "Continue?" "y" || die "aborted by user"
    else
        mkdir -p "$USB_DIR"
    fi
    chmod 700 "$USB_DIR" 2>/dev/null || true

    BACKUP_SSH="n"
    if [[ -d "$HOME/.ssh" ]]; then
        if ux_confirm "Back up ~/.ssh/ as well? (recommended if you need to clone on a fresh PC)" "y"; then
            BACKUP_SSH="y"
        fi
    else
        ux_warning "no ~/.ssh/ directory found — skipping SSH backup"
    fi

    # Transport passphrase: prompt twice via gpg's own pinentry, but we collect
    # once into a mode-600 file and reuse for --passphrase-file.
    ux_info "You will now set a TRANSPORT passphrase used to encrypt the 3 files."
    ux_info "Store this passphrase in your password manager (NOT on the USB)."
    PASS_FILE="$WORKDIR/pw"
    touch "$PASS_FILE"
    chmod 600 "$PASS_FILE"

    # Read with confirmation; suppress echo.
    local p1 p2
    while :; do
        read -r -s -p "  Transport passphrase: " p1 && echo
        read -r -s -p "  Confirm passphrase:   " p2 && echo
        if [[ "$p1" != "$p2" ]]; then
            ux_warning "mismatch — try again"
            continue
        fi
        if ((${#p1} < 12)); then
            ux_warning "too short (< 12 chars) — try again"
            continue
        fi
        printf '%s' "$p1" >"$PASS_FILE"
        unset p1 p2
        break
    done
    echo ""
}

# ----------------------------------------------------------------------------
# Shared helper: symmetric-encrypt a plaintext file to a target on USB.
# Uses passphrase-file for non-interactive operation.
# ----------------------------------------------------------------------------
symmetric_wrap() {
    local src="$1" dst="$2"
    gpg --batch --yes --pinentry-mode loopback \
        --passphrase-file "$PASS_FILE" \
        --symmetric --cipher-algo AES256 --armor \
        --output "$dst" "$src"
}

# ----------------------------------------------------------------------------
# Step 2: (A) GPG private key
# ----------------------------------------------------------------------------
backup_gpg_key() {
    ux_step "2/5" "Backing up GPG private key"

    local plain="$WORKDIR/gpg-priv.asc"
    # --export-secret-keys already prompts for the KEY passphrase interactively.
    ux_info "GPG will now ask for your GPG private key passphrase..."
    gpg --export-secret-keys --armor "$GPG_SHORT_ID" >"$plain"
    [[ -s "$plain" ]] || die "GPG export produced empty output"

    GPG_OUT="$USB_DIR/01-gpg-privkey-${GPG_SHORT_ID}.asc.gpg"
    symmetric_wrap "$plain" "$GPG_OUT"
    shred -u "$plain" 2>/dev/null || rm -f "$plain"
    ux_success "GPG key → $(basename "$GPG_OUT") ($(file_size_h "$GPG_OUT"))"
    echo ""
}

# ----------------------------------------------------------------------------
# Step 3: (B) git-crypt master key
# ----------------------------------------------------------------------------
backup_gitcrypt_key() {
    ux_step "3/5" "Backing up git-crypt master key"

    local plain="$WORKDIR/gc-master.key"
    git-crypt export-key "$plain" || die "git-crypt export-key failed (is the repo unlocked?)"
    [[ -s "$plain" ]] || die "git-crypt export produced empty output"

    GC_OUT="$USB_DIR/02-git-crypt-master.key.gpg"
    symmetric_wrap "$plain" "$GC_OUT"
    shred -u "$plain" 2>/dev/null || rm -f "$plain"
    ux_success "git-crypt key → $(basename "$GC_OUT") ($(file_size_h "$GC_OUT"))"
    echo ""
}

# ----------------------------------------------------------------------------
# Step 4: (C) SSH keys (optional)
# ----------------------------------------------------------------------------
backup_ssh_keys() {
    if [[ "$BACKUP_SSH" != "y" ]]; then
        ux_step "4/5" "SSH backup skipped (per user choice)"
        SSH_OUT=""
        echo ""
        return 0
    fi

    ux_step "4/5" "Backing up ~/.ssh/"

    local plain="$WORKDIR/ssh.tar"
    (cd "$HOME" && tar cf "$plain" .ssh)
    [[ -s "$plain" ]] || die "tar of ~/.ssh/ produced empty output"

    SSH_OUT="$USB_DIR/03-ssh-$(hostname -s).tar.gpg"
    symmetric_wrap "$plain" "$SSH_OUT"
    shred -u "$plain" 2>/dev/null || rm -f "$plain"
    ux_success "SSH archive → $(basename "$SSH_OUT") ($(file_size_h "$SSH_OUT"))"
    echo ""
}

# ----------------------------------------------------------------------------
# Step 5: (D) Plaintext metadata + on-screen summary
# ----------------------------------------------------------------------------
write_summary() {
    ux_step "5/5" "Writing metadata & summary"

    local meta="$USB_DIR/04-recovery-metadata.txt"
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local repo_url
    repo_url="$(git -C "$DOTFILES_ROOT" remote get-url origin 2>/dev/null || echo "(unknown)")"

    # Gather GPG key details.
    local gpg_line
    gpg_line="$(gpg --list-secret-keys --keyid-format=long --with-colons "$GPG_SHORT_ID" \
        2>/dev/null | awk -F: '$1=="sec"{print $5" "$6" "$7; exit}')"
    # gpg_line: KEYID CREATED EXPIRY(epoch, empty if no expiry)
    local gpg_created gpg_expires
    gpg_created="$(echo "$gpg_line" | awk '{print $2}')"
    gpg_expires="$(echo "$gpg_line" | awk '{print $3}')"
    [[ -n "$gpg_created" && "$gpg_created" != "0" ]] &&
        gpg_created="$(date -u -d "@$gpg_created" +%Y-%m-%d 2>/dev/null || echo "$gpg_created")"
    [[ -n "$gpg_expires" && "$gpg_expires" != "0" ]] &&
        gpg_expires="$(date -u -d "@$gpg_expires" +%Y-%m-%d 2>/dev/null || echo "$gpg_expires")" ||
        gpg_expires="(never)"

    # Pre-compute checksums so both the on-screen block and the metadata file show the same digest.
    local gpg_sha gc_sha ssh_sha
    gpg_sha="$(sha256_of "$GPG_OUT")"
    gc_sha="$(sha256_of "$GC_OUT")"
    [[ -n "$SSH_OUT" ]] && ssh_sha="$(sha256_of "$SSH_OUT")" || ssh_sha=""

    # -------- Build the summary text (reused for on-screen and metadata file) --------
    SUMMARY="$(
        cat <<EOF
============================================================
   GIT-CRYPT RECOVERY BACKUP — SUMMARY
============================================================

DATE (UTC):   $now
HOST:         $(hostname -s)
USB PATH:     $USB_DIR/

------------------------------------------------------------
FILES ON USB
------------------------------------------------------------
  01-gpg-privkey-${GPG_SHORT_ID}.asc.gpg
     size   : $(file_size_h "$GPG_OUT")
     sha256 : $gpg_sha

  02-git-crypt-master.key.gpg
     size   : $(file_size_h "$GC_OUT")
     sha256 : $gc_sha
EOF
    )"
    if [[ -n "$SSH_OUT" ]]; then
        SUMMARY="$SUMMARY
$(
            cat <<EOF

  $(basename "$SSH_OUT")
     size   : $(file_size_h "$SSH_OUT")
     sha256 : $ssh_sha
EOF
        )"
    else
        SUMMARY="$SUMMARY

  (SSH backup skipped)"
    fi

    SUMMARY="$SUMMARY
$(
        cat <<EOF

  04-recovery-metadata.txt     (plaintext — this file)

------------------------------------------------------------
GPG KEY
------------------------------------------------------------
  Key ID      : $GPG_SHORT_ID
  Fingerprint : $GPG_FPR
  Created     : $gpg_created
  Expires     : $gpg_expires

------------------------------------------------------------
REPO
------------------------------------------------------------
  $repo_url

------------------------------------------------------------
RECOVERY ORDER (on a fresh PC)
------------------------------------------------------------
  1. Install tools: git, gpg, git-crypt, openssh-client
  2. If 03-*.tar.gpg present:
        gpg --decrypt <file> | tar xf - -C ~
        chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*
  3. git clone $repo_url
  4. Restore GPG key (Plan A):
        gpg --decrypt 01-*.asc.gpg | gpg --import
  5. bash shell-common/tools/custom/bootstrap_git_crypt.sh
        (was: setup_new_pc.sh — see issue #124 for the rename)

  FALLBACK (Plan B) — if GPG restoration fails:
        gpg --decrypt 02-git-crypt-master.key.gpg > /tmp/k
        cd ~/dotfiles && git-crypt unlock /tmp/k
        shred -u /tmp/k

------------------------------------------------------------
PASSPHRASES — DO NOT WRITE ON PAPER / IN THIS FILE
------------------------------------------------------------
  [A] Transport passphrase (the one you just typed)
      -> store: password manager
  [B] GPG private key passphrase (original key creation)
      -> store: password manager (separate entry)

============================================================
EOF
    )"

    # Write metadata file (plaintext, safe).
    printf '%s\n' "$SUMMARY" >"$meta"
    chmod 600 "$meta" 2>/dev/null || true
    ux_success "metadata → $(basename "$meta")"
    echo ""
}

print_summary_block() {
    # Render the summary as a clearly delimited block for easy transcription.
    echo ""
    ux_divider_thick
    echo ""
    printf '%s\n' "$SUMMARY"
    echo ""
    ux_divider_thick
    echo ""
    ux_info "Same content saved to: $USB_DIR/04-recovery-metadata.txt"
    ux_info "Transcribe the block above (or copy from the metadata file) to your notebook / Obsidian / OneNote."
    ux_info "Remember to 'sync' and safely eject the USB before unplugging."
    echo ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    clear
    ux_header "Git-crypt USB Recovery Backup"
    ux_info "This script creates encrypted backups on a USB drive so you can"
    ux_info "restore git-crypt access on a brand-new PC."
    echo ""

    preflight
    ask_inputs
    backup_gpg_key
    backup_gitcrypt_key
    backup_ssh_keys
    write_summary
    print_summary_block
}

# Direct-exec guard (same pattern as other custom tools)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
