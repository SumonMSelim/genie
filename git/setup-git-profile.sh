#!/bin/bash

# Genie - Git Profile Setup
#
# Sets up a named git identity (SSH key, GPG key, per-directory gitconfig)
# for any git provider: GitHub, GitLab, Bitbucket, Gitea, Azure DevOps,
# or any self-hosted instance.
#
# Run once per profile. Idempotent — safe to re-run.
#
# COMPATIBILITY: macOS, Ubuntu/Debian Linux

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Output helpers ─────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}── $1${NC}"; }

# NOTE: Returns exit code 1 on "no". With set -e active, always call inside
# `if ask_confirm ...` or `ask_confirm ... || true` — a bare "no" exits the script.
ask_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local choice

    if [[ "$default" == "Y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -rp "$(echo -e "${YELLOW}??${NC} $prompt")" choice
    choice="${choice:-$default}"
    [[ "$choice" =~ ^[Yy]$ ]]
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ── Profile variables (populated by collect_profile_info) ─────────────────────
PROFILE_NAME=""
DISPLAY_NAME=""
EMAIL=""
GIT_USERNAME=""
WORK_DIR=""
WORK_DIR_EXPANDED=""
PROVIDER=""
PROVIDER_HOSTNAME=""
SSH_PORT="22"
GPG_SUPPORTED="true"
GPG_KEY_ID=""
SSH_KEY_PATH=""
SSH_ALIAS=""
OS=""  # set once in main() to avoid repeated $OS subshells

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
   ____            _
  / ___| ___ _ __ (_) ___
 | |  _ / _ \ '_ \| |/ _ \
 | |_| |  __/ | | | |  __/
  \____|\___|_| |_|_|\___|

EOF
    echo -e "${NC}"
    info "Git Profile Setup"
    info "Author: Muhammad Sumon Molla Selim"
    info "GitHub: https://github.com/SumonMSelim/genie"
    echo ""
}

# ── Step 1: Collect profile information ───────────────────────────────────────
collect_profile_info() {
    step "Profile Information"

    # Profile name (slug)
    while true; do
        read -rp "$(echo -e "${YELLOW}??${NC} Profile name (e.g. 'personal', 'work'): ")" PROFILE_NAME
        # Portable lowercase + hyphenate spaces (no bash 4 required)
        PROFILE_NAME=$(echo "$PROFILE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if [[ "$PROFILE_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            break
        fi
        warn "Must start with a letter/digit and contain only [a-z0-9_-]."
    done

    read -rp "$(echo -e "${YELLOW}??${NC} Display name (e.g. 'John Doe'): ")" DISPLAY_NAME
    DISPLAY_NAME=$(echo "$DISPLAY_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$DISPLAY_NAME" ]] && error "Display name cannot be empty."
    read -rp "$(echo -e "${YELLOW}??${NC} Email address: ")" EMAIL
    EMAIL="${EMAIL//[[:space:]]/}"
    [[ "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || warn "Email format looks invalid: $EMAIL"
    read -rp "$(echo -e "${YELLOW}??${NC} Git provider username: ")" GIT_USERNAME
    GIT_USERNAME="${GIT_USERNAME//[[:space:]]/}"
    [[ -z "$GIT_USERNAME" ]] && error "Username cannot be empty."
    read -rp "$(echo -e "${YELLOW}??${NC} Work directory (e.g. ~/Work): ")" WORK_DIR
    WORK_DIR=$(echo "$WORK_DIR" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ "$WORK_DIR" != /* && "$WORK_DIR" != ~* ]] && error "Work directory must be an absolute path or start with ~"
    WORK_DIR_EXPANDED="${WORK_DIR/#\~/$HOME}"

    # Provider selection
    step "Git Provider"
    echo ""
    echo "  1) GitHub        (github.com)"
    echo "  2) GitLab        (gitlab.com)"
    echo "  3) Bitbucket     (bitbucket.org)"
    echo "  4) Gitea         (self-hosted or gitea.io)"
    echo "  5) Azure DevOps  (ssh.dev.azure.com)"
    echo "  6) Custom        (enter hostname manually)"
    echo ""

    local choice
    while true; do
        read -rp "$(echo -e "${YELLOW}??${NC} Select provider [1-6]: ")" choice
        case "$choice" in
            1) PROVIDER="github";    PROVIDER_HOSTNAME="github.com";        GPG_SUPPORTED="true";  break ;;
            2) PROVIDER="gitlab";    PROVIDER_HOSTNAME="gitlab.com";        GPG_SUPPORTED="true";  break ;;
            3) PROVIDER="bitbucket"; PROVIDER_HOSTNAME="bitbucket.org";     GPG_SUPPORTED="false"; break ;;
            4) PROVIDER="gitea"
               read -rp "$(echo -e "${YELLOW}??${NC} Gitea hostname (e.g. gitea.io or git.example.com): ")" PROVIDER_HOSTNAME
               GPG_SUPPORTED="true"; break ;;
            5) PROVIDER="azure";     PROVIDER_HOSTNAME="ssh.dev.azure.com"; GPG_SUPPORTED="false"; break ;;
            6) PROVIDER="custom"
               read -rp "$(echo -e "${YELLOW}??${NC} Hostname (e.g. git.example.com): ")" PROVIDER_HOSTNAME
               GPG_SUPPORTED="true"; break ;;
            *) warn "Please enter a number between 1 and 6." ;;
        esac
    done

    # Optional: non-standard SSH port
    local custom_port
    read -rp "$(echo -e "${YELLOW}??${NC} SSH port [default: 22]: ")" custom_port
    [[ -n "$custom_port" && (! "$custom_port" =~ ^[0-9]+$ || "$custom_port" -lt 1 || "$custom_port" -gt 65535) ]] && error "SSH port must be a number between 1 and 65535."
    SSH_PORT="${custom_port:-22}"

    PROVIDER_HOSTNAME="${PROVIDER_HOSTNAME//[[:space:]]/}"
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519_${PROFILE_NAME}"
    SSH_ALIAS="${PROVIDER_HOSTNAME}-${PROFILE_NAME}"

    # Confirm
    echo ""
    echo -e "${BOLD}Profile summary:${NC}"
    echo "  Profile name   : $PROFILE_NAME"
    echo "  Display name   : $DISPLAY_NAME"
    echo "  Email          : $EMAIL"
    echo "  Username       : $GIT_USERNAME"
    echo "  Work directory : $WORK_DIR"
    echo "  Provider       : $PROVIDER ($PROVIDER_HOSTNAME)"
    echo "  SSH alias      : $SSH_ALIAS"
    echo "  SSH port       : $SSH_PORT"
    echo "  GPG signing    : $GPG_SUPPORTED"
    echo ""

    if ! ask_confirm "Proceed with this configuration?"; then
        echo "Aborted."
        exit 0
    fi
}

# ── Step 2: Work directory ─────────────────────────────────────────────────────
step_work_directory() {
    step "Work Directory"

    if [[ -d "$WORK_DIR_EXPANDED" ]]; then
        info "Directory '$WORK_DIR' already exists."
        return 0
    fi

    if ask_confirm "Create directory '$WORK_DIR'?"; then
        mkdir -p "$WORK_DIR_EXPANDED"
        success "Created $WORK_DIR"
    else
        warn "Skipped. The includeIf git config will still be written — create the directory before using it."
    fi
}

# ── Step 3: SSH key ────────────────────────────────────────────────────────────
step_ssh_key() {
    step "SSH Key"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [[ -f "$SSH_KEY_PATH" ]]; then
        warn "SSH key already exists at $SSH_KEY_PATH"
        if ask_confirm "Use existing key (skip generation)?"; then
            return 0
        fi
        if ! ask_confirm "Overwrite it? The old key will be permanently lost." "N"; then
            echo "Aborting."
            exit 0
        fi
        rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    fi

    info "Generating ED25519 SSH key: $SSH_KEY_PATH"
    echo ""

    local passphrase=""
    local passphrase_confirm=""
    if ask_confirm "Protect the key with a passphrase? (recommended; ssh-agent handles it transparently)"; then
        while true; do
            read -rsp "$(echo -e "${YELLOW}??${NC} Passphrase: ")" passphrase
            echo ""
            read -rsp "$(echo -e "${YELLOW}??${NC} Confirm passphrase: ")" passphrase_confirm
            echo ""
            if [[ "$passphrase" == "$passphrase_confirm" ]]; then
                break
            fi
            warn "Passphrases do not match. Try again."
        done
    fi

    # -N passes the passphrase as a CLI arg (visible in /proc on Linux while running).
    # Acceptable for personal tooling; for shared systems consider SSH_ASKPASS instead.
    ssh-keygen -t ed25519 -C "${EMAIL}" -f "$SSH_KEY_PATH" -N "$passphrase"
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
    success "SSH key generated: $SSH_KEY_PATH"

    # macOS: offer to add to system keychain
    if [[ "$OS" == "Darwin" ]] && [[ -n "$passphrase" ]]; then
        if ask_confirm "Add key to macOS keychain (ssh-add --apple-use-keychain)?"; then
            ssh-add --apple-use-keychain "$SSH_KEY_PATH" 2>/dev/null \
                && success "Key added to macOS keychain." \
                || warn "Could not add to keychain — add it manually: ssh-add --apple-use-keychain $SSH_KEY_PATH"
        fi
    elif [[ "$OS" != "Darwin" ]] && [[ -n "$passphrase" ]]; then
        info "Remember to run: ssh-add $SSH_KEY_PATH"
    fi
}

# ── Step 4: SSH config ─────────────────────────────────────────────────────────
step_ssh_config() {
    step "SSH Config  (~/.ssh/config)"

    local ssh_config="$HOME/.ssh/config"

    if grep -q "^Host ${SSH_ALIAS}$" "$ssh_config" 2>/dev/null; then
        warn "SSH config entry for '${SSH_ALIAS}' already exists. Skipping."
        return 0
    fi

    touch "$ssh_config"
    chmod 600 "$ssh_config"

    {
        echo ""
        echo "# Profile: ${PROFILE_NAME} (${PROVIDER})"
        echo "Host ${SSH_ALIAS}"
        echo "    HostName ${PROVIDER_HOSTNAME}"
        echo "    User git"
        echo "    IdentityFile ${SSH_KEY_PATH}"
        echo "    AddKeysToAgent yes"
        echo "    IdentitiesOnly yes"
        if [[ "$SSH_PORT" != "22" ]]; then
            echo "    Port ${SSH_PORT}"
        fi
        # UseKeychain yes is harmless for passphrase-less keys; it only
        # takes effect when a passphrase is present in the macOS keychain.
        if [[ "$OS" == "Darwin" ]]; then
            echo "    UseKeychain yes"
        fi
    } >> "$ssh_config"

    success "SSH config entry added: Host ${SSH_ALIAS}"
}

# ── Step 5: GPG key ────────────────────────────────────────────────────────────
step_gpg() {
    step "GPG Signing Key"

    if [[ "$GPG_SUPPORTED" == "false" ]]; then
        warn "${PROVIDER} does not support GPG commit verification — skipping GPG setup."
        info "Commits will not have a 'Verified' badge on ${PROVIDER}."
        return 0
    fi

    # Ensure gpg is installed
    if ! command_exists gpg; then
        warn "gpg not found."
        if [[ "$OS" == "Darwin" ]] && command_exists brew; then
            if ask_confirm "Install gnupg + pinentry-mac via Homebrew?"; then
                brew install gnupg pinentry-mac
                # Point gpg-agent at pinentry-mac so passphrase dialogs work in Terminal
                mkdir -p "$HOME/.gnupg"
                chmod 700 "$HOME/.gnupg"
                local agent_conf="$HOME/.gnupg/gpg-agent.conf"
                if ! grep -q "pinentry-program" "$agent_conf" 2>/dev/null; then
                    echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> "$agent_conf"
                fi
                gpgconf --kill gpg-agent 2>/dev/null || true
            else
                warn "Skipping GPG setup."
                return 0
            fi
        elif command_exists apt-get; then
            if ask_confirm "Install gnupg via apt?"; then
                sudo apt-get install -y gnupg
            else
                warn "Skipping GPG setup."
                return 0
            fi
        else
            warn "Cannot install gpg automatically. Install it manually and re-run."
            return 0
        fi
    fi

    echo ""
    echo "  1) Generate a new GPG key for this profile"
    echo "  2) Use an existing GPG key (provide key ID)"
    echo "  3) Skip GPG signing for this profile"
    echo ""

    local choice
    while true; do
        read -rp "$(echo -e "${YELLOW}??${NC} GPG option [1-3]: ")" choice
        case "$choice" in
            1)
                info "Starting interactive GPG key generation."
                info "Tip: choose RSA / 4096 bits / 1 year expiry, and use email: ${EMAIL}"
                echo ""
                gpg --full-generate-key
                # Extract the new key ID by email
                GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long "${EMAIL}" 2>/dev/null \
                    | grep -E "^sec" | head -1 | awk '{print $2}' | awk -F'/' '{print $NF}')
                if [[ -z "$GPG_KEY_ID" ]]; then
                    warn "Could not auto-detect key ID."
                    gpg --list-secret-keys --keyid-format=long 2>/dev/null || true
                    read -rp "$(echo -e "${YELLOW}??${NC} Enter GPG key ID manually (long format): ")" GPG_KEY_ID
                else
                    success "Detected GPG key ID: ${GPG_KEY_ID}"
                fi
                command_exists gpg && git config --global gpg.program "$(command -v gpg)"
                break
                ;;
            2)
                echo ""
                info "Your existing secret keys:"
                gpg --list-secret-keys --keyid-format=long 2>/dev/null || true
                echo ""
                read -rp "$(echo -e "${YELLOW}??${NC} Enter GPG key ID (long format, e.g. A1B2C3D4E5F60708): ")" GPG_KEY_ID
                if ! gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
                    warn "Key '${GPG_KEY_ID}' not found in local keyring — proceeding anyway."
                fi
                command_exists gpg && git config --global gpg.program "$(command -v gpg)"
                break
                ;;
            3)
                GPG_KEY_ID=""
                info "GPG signing skipped for this profile."
                break
                ;;
            *)
                warn "Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# ── Step 6: Per-profile gitconfig ──────────────────────────────────────────────
step_gitconfig_profile() {
    step "Per-profile Git Config  (~/.gitconfig-${PROFILE_NAME})"

    local profile_config="$HOME/.gitconfig-${PROFILE_NAME}"

    if [[ -f "$profile_config" ]]; then
        warn "Profile config already exists at $profile_config"
        if ! ask_confirm "Overwrite it?"; then
            return 0
        fi
    fi

    {
        echo "[user]"
        echo "    name  = ${DISPLAY_NAME}"
        echo "    email = ${EMAIL}"
        if [[ -n "$GPG_KEY_ID" ]]; then
            echo "    signingkey = ${GPG_KEY_ID}"
        fi
    } > "$profile_config"

    if [[ -n "$GPG_KEY_ID" ]]; then
        {
            echo ""
            echo "[commit]"
            echo "    gpgsign = true"
            echo ""
            echo "[tag]"
            echo "    gpgsign = true"
        } >> "$profile_config"
    fi

    success "Written: $profile_config"
    echo ""
    cat "$profile_config"
}

# ── Step 7: Global gitconfig includeIf + url.insteadOf ────────────────────────
step_gitconfig_global() {
    step "Global Git Config  (~/.gitconfig — includeIf + url.insteadOf)"

    local global_config="$HOME/.gitconfig"
    local work_dir_config="${WORK_DIR%/}/"

    touch "$global_config"

    # includeIf: apply per-profile identity inside the work directory
    if grep -q "gitdir:${work_dir_config}\"" "$global_config" 2>/dev/null; then
        warn "includeIf for '${work_dir_config}' is already in ~/.gitconfig — skipping."
    else
        {
            echo ""
            echo "# Profile: ${PROFILE_NAME} (${PROVIDER})"
            echo "[includeIf \"gitdir:${work_dir_config}\"]"
            echo "    path = ~/.gitconfig-${PROFILE_NAME}"
        } >> "$global_config"
        success "Added includeIf for '${work_dir_config}' → ~/.gitconfig-${PROFILE_NAME}"
    fi

    # url.insteadOf: `git clone personal:user/repo` → `git@github.com-personal:user/repo`
    if grep -Fq "insteadOf = ${PROFILE_NAME}:" "$global_config" 2>/dev/null; then
        warn "url.insteadOf for '${PROFILE_NAME}:' already in ~/.gitconfig — skipping."
    else
        {
            echo ""
            echo "# Clone shorthand: git clone ${PROFILE_NAME}:user/repo"
            echo "[url \"git@${SSH_ALIAS}:\"]"
            echo "    insteadOf = ${PROFILE_NAME}:"
        } >> "$global_config"
        success "Added url.insteadOf: '${PROFILE_NAME}:' → 'git@${SSH_ALIAS}:'"
    fi
}

# ── Step 8: Profile map + gclone helper ───────────────────────────────────────
PROFILE_MAP="$HOME/.config/git-profiles"
GCLONE_HELPER="$HOME/.config/genie/gclone.sh"

step_profile_map() {
    step "Profile Map + gclone Helper"

    mkdir -p "$HOME/.config/genie"

    # ── Profile map ──
    if [[ ! -f "$PROFILE_MAP" ]]; then
        {
            echo "# Managed by genie/git/setup-git-profile.sh"
            echo "# Format: <work-directory>  <ssh-alias>  <profile-name>"
        } > "$PROFILE_MAP"
    fi

    if grep -q "^${WORK_DIR%/}/" "$PROFILE_MAP" 2>/dev/null; then
        warn "Profile map entry for '${WORK_DIR}' already exists — skipping."
    else
        printf "%-30s %-35s %s\n" "${WORK_DIR%/}/" "${SSH_ALIAS}" "${PROFILE_NAME}" >> "$PROFILE_MAP"
        success "Profile map updated: $PROFILE_MAP"
    fi

    # ── gclone helper (written once; shared across all profiles) ──
    if [[ -f "$GCLONE_HELPER" ]]; then
        info "gclone helper already exists at $GCLONE_HELPER"
        return 0
    fi

    cat > "$GCLONE_HELPER" << 'GCLONE_EOF'
# gclone — directory-aware git clone helper
# Managed by genie/git/setup-git-profile.sh
#
# Reads ~/.config/git-profiles to pick the right SSH alias automatically.
#
# Usage:
#   gclone user/repo [dest]          auto-detects profile from $PWD
#   gclone -p profile user/repo      explicit profile, works from anywhere
#
# Add to ~/.zshrc or ~/.bashrc:
#   source ~/.config/genie/gclone.sh

gclone() {
    local repo="" dest="" profile_flag=""
    local profile_map="$HOME/.config/git-profiles"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--profile)
                [[ -z "$2" || "$2" == -* ]] && { echo "gclone: -p requires a profile name"; return 1; }
                profile_flag="$2"; shift 2 ;;
            -*) echo "gclone: unknown option '$1'"; return 1 ;;
            *) [[ -z "$repo" ]] && repo="$1" || dest="$1"; shift ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        echo "Usage: gclone [-p profile] user/repo [dest]"
        echo "       gclone sumon/dotfiles              # auto-detect from \$PWD"
        echo "       gclone -p personal sumon/dotfiles  # explicit profile"
        return 1
    fi

    [[ "$repo" == *"://"* || "$repo" == "git@"* ]] && { echo "gclone: provide 'user/repo', not a full URL"; return 1; }

    if [[ ! -f "$profile_map" ]]; then
        echo "gclone: profile map not found at $profile_map"
        echo "Run genie/git/setup-git-profile.sh to create a profile."
        return 1
    fi

    local matched_alias="" current_dir="$PWD"
    local dir al prof dir_expanded

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" ]] && continue
        read -r dir al prof <<< "$line"

        if [[ -n "$profile_flag" ]]; then
            if [[ "$prof" == "$profile_flag" ]]; then
                matched_alias="$al"; break
            fi
        else
            dir_expanded="${dir/#\~/$HOME}"
            dir_expanded="${dir_expanded%/}"
            if [[ "$current_dir" == "$dir_expanded" || "$current_dir" == "$dir_expanded/"* ]]; then
                matched_alias="$al"; break
            fi
        fi
    done < "$profile_map"

    if [[ -z "$matched_alias" ]]; then
        if [[ -n "$profile_flag" ]]; then
            echo "gclone: profile '${profile_flag}' not found in $profile_map"
        else
            echo "gclone: no profile mapped to '$current_dir'"
            echo "Tip: use gclone -p <profile> user/repo to specify explicitly."
        fi
        echo ""
        echo "Registered profiles:"
        grep -v "^#" "$profile_map" | grep -v "^[[:space:]]*$" \
            | awk '{printf "  %-15s %s\n", $3, $1}' 2>/dev/null || true
        return 1
    fi

    local url="git@${matched_alias}:${repo}"
    echo "→ git clone ${url}${dest:+ ${dest}}"
    git clone "$url" ${dest:+"$dest"}
}
GCLONE_EOF

    success "gclone helper written: $GCLONE_HELPER"
}

# ── Step 9: Test SSH connection ────────────────────────────────────────────────
step_test_ssh() {
    step "Test SSH Connection"

    info "This requires the SSH public key to already be added to your ${PROVIDER} account."
    if ! ask_confirm "Test SSH connection to '${SSH_ALIAS}' now?"; then
        return 0
    fi

    echo ""
    info "Running: ssh -T git@${SSH_ALIAS}"
    info "(Exit code 1 is normal for GitHub/GitLab — it means auth succeeded but no shell.)"
    echo ""
    ssh -T "git@${SSH_ALIAS}" 2>&1 || true
    echo ""
    info "If you saw 'Hi ${GIT_USERNAME}!' or 'Welcome to GitLab, ${DISPLAY_NAME}!' above, you're connected."
}

# ── Step 10: Summary ───────────────────────────────────────────────────────────
step_summary() {
    step "Setup Complete — Next Steps"

    local pub_key n=0
    pub_key=$(cat "${SSH_KEY_PATH}.pub" 2>/dev/null || echo "(key not found at ${SSH_KEY_PATH}.pub)")

    # ── SSH key ──
    n=$(( n + 1 ))
    echo ""
    echo -e "${BOLD}${n}. Add your SSH public key to ${PROVIDER}${NC}"
    echo ""
    echo -e "   ${CYAN}${pub_key}${NC}"
    echo ""
    case "$PROVIDER" in
        github)    echo "   -> https://github.com/settings/ssh/new" ;;
        gitlab)    echo "   -> https://gitlab.com/-/profile/keys" ;;
        bitbucket) echo "   -> https://bitbucket.org/account/settings/ssh-keys/" ;;
        gitea)     echo "   -> https://${PROVIDER_HOSTNAME}/-/user/settings/keys" ;;
        azure)     echo "   -> https://dev.azure.com/${GIT_USERNAME}/_usersSettings/keys" ;;
        *)         echo "   -> Your provider's SSH keys settings page." ;;
    esac

    # ── GPG key ──
    if [[ -n "$GPG_KEY_ID" ]]; then
        n=$(( n + 1 ))
        echo ""
        echo -e "${BOLD}${n}. Add your GPG public key to ${PROVIDER}${NC}"
        echo ""
        gpg --armor --export "$GPG_KEY_ID" 2>/dev/null || warn "Could not export GPG key ${GPG_KEY_ID}"
        echo ""
        case "$PROVIDER" in
            github) echo "   -> https://github.com/settings/gpg/new" ;;
            gitlab) echo "   -> https://gitlab.com/-/profile/gpg_keys" ;;
            gitea)  echo "   -> https://${PROVIDER_HOSTNAME}/-/user/settings/keys" ;;
        esac
    fi

    # ── gclone source line ──
    n=$(( n + 1 ))
    echo ""
    echo -e "${BOLD}${n}. Enable gclone — add to ~/.zshrc or ~/.bashrc${NC}"
    echo ""
    echo "   source ~/.config/genie/gclone.sh"
    echo ""
    echo "   (Already written to: $GCLONE_HELPER)"

    # ── Cloning ──
    n=$(( n + 1 ))
    echo ""
    echo -e "${BOLD}${n}. Clone repositories — two ways${NC}"
    echo ""
    echo -e "   ${CYAN}a) From anywhere — git url.insteadOf shorthand:${NC}"
    echo ""
    case "$PROVIDER" in
        azure)
            echo "      git clone ${PROFILE_NAME}:v3/{org}/{project}/{repo}"
            ;;
        *)
            echo "      git clone ${PROFILE_NAME}:${GIT_USERNAME}/my-repo"
            ;;
    esac
    echo ""
    echo -e "   ${CYAN}b) Auto-detect from current directory — gclone:${NC}"
    echo ""
    echo "      cd ${WORK_DIR} && gclone ${GIT_USERNAME}/my-repo"
    echo "      gclone -p ${PROFILE_NAME} ${GIT_USERNAME}/my-repo   # explicit, works from anywhere"

    # ── Verify ──
    n=$(( n + 1 ))
    echo ""
    echo -e "${BOLD}${n}. Verify identity inside a repo in ${WORK_DIR}${NC}"
    echo ""
    echo "   cd ${WORK_DIR}/<any-repo>"
    echo "   git config user.email   # expects: ${EMAIL}"
    echo "   git config user.name    # expects: ${DISPLAY_NAME}"

    echo ""
    success "Profile '${PROFILE_NAME}' is ready."
    echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    OS="$(uname)"
    command_exists git || error "git is not installed."
    print_banner
    collect_profile_info
    step_work_directory
    step_ssh_key
    step_ssh_config
    step_gpg
    step_gitconfig_profile
    step_gitconfig_global
    step_profile_map
    step_test_ssh
    step_summary
}

main
