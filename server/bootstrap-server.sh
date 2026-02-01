#!/bin/bash

# Genie Server Bootstrapping Script for Debian/Ubuntu
#
# COMPATIBILITY:
# - Ubuntu: 20.04 LTS (Focal), 22.04 LTS (Jammy), 24.04 LTS (Noble)
# - Debian: 11 (Bullseye), 12 (Bookworm)

set -e

# Colors for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output helpers
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

pkg_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

apt_update_once() {
    if [[ "${APT_UPDATED:-false}" == "true" ]]; then
        return 0
    fi
    if ask_confirm "Run apt update now? (recommended)" "Y"; then
        apt update
        APT_UPDATED=true
        return 0
    fi
    return 1
}

ensure_pkg() {
    local pkg="$1"
    local purpose="${2:-}"

    if pkg_installed "$pkg"; then
        return 0
    fi

    if ask_confirm "Install '$pkg'${purpose:+ ($purpose)}?"; then
        if apt install -y "$pkg"; then
            return 0
        fi

        warn "Failed to install '$pkg'."
        if ask_confirm "Try 'apt update' and retry installing '$pkg'?" "Y"; then
            if apt_update_once && apt install -y "$pkg"; then
                return 0
            fi
        fi
    fi

    warn "Skipping (missing: $pkg)."
    return 1
}

ensure_cmd() {
    local cmd="$1"
    local pkg="$2"
    local purpose="${3:-}"

    if command_exists "$cmd"; then
        return 0
    fi

    if ensure_pkg "$pkg" "${purpose:-provides '$cmd'}"; then
        return 0
    fi

    warn "Skipping (missing command: $cmd)."
    return 1
}

run_as_user() {
    # run_as_user <user> <command>
    # Ensures HOME is the target user's home so installers (e.g. Oh My Zsh) can cd there.
    local user="$1"
    shift
    local cmd="$*"

    if [[ "$user" == "root" ]]; then
        bash -lc "$cmd"
        return $?
    fi

    if command_exists sudo; then
        # -H sets HOME to target user's home (fixes "cd: can't cd to /root" when running as non-root)
        sudo -H -u "$user" bash -lc "$cmd"
        return $?
    fi

    if command_exists su; then
        # Login shell so HOME is set to target user's home
        su - "$user" -c "bash -lc $(printf '%q' "$cmd")"
        return $?
    fi

    warn "Neither sudo nor su is available; cannot run commands as '$user'."
    return 1
}

append_line_if_missing() {
    local line="$1"
    local file="$2"
    touch "$file"
    if ! grep -Fxq "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
    fi
}

restart_ssh_service() {
    if command_exists systemctl; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || return 1
        return 0
    fi

    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || return 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo."
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        return 0
    fi

    error "Cannot detect OS. This script requires a Debian or Ubuntu based system."
    exit 1
}

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
    info "Welcome to the Genie Server Bootstrapping Script!"
    info "Detected OS: ${OS^} $VER"
    info "Author: Muhammad Sumon Molla Selim"
    info "GitHub: https://github.com/SumonMSelim/genie"
    echo ""
}

setup_zsh_for_user() {
    local target_user="$1"
    local target_home
    local changed_shell=false

    if [[ "$target_user" == "root" ]]; then
        target_home="/root"
    else
        target_home="/home/$target_user"
    fi

    info "Setting up Zsh for $target_user..."

    if ! ensure_cmd zsh zsh "shell"; then
        warn "Skipping Zsh setup for $target_user."
        return 0
    fi

    # Ensure zsh is in /etc/shells for chsh
    append_line_if_missing "$(which zsh)" "/etc/shells"

    # Oh My Zsh
    if [[ ! -d "$target_home/.oh-my-zsh" ]]; then
        if ask_confirm "Install Oh My Zsh for $target_user?"; then
            # Oh My Zsh's installer relies on both curl and git.
            if ensure_cmd curl curl "download helper" && ensure_cmd git git "required by Oh My Zsh installer"; then
                if ! run_as_user "$target_user" "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"; then
                    warn "Oh My Zsh install failed for $target_user (continuing)."
                fi
            else
                warn "Skipping Oh My Zsh install for $target_user (missing dependencies)."
            fi
        fi
    fi

    # Plugins (requires git)
    if [[ -d "$target_home/.oh-my-zsh" ]]; then
        local custom_dir="$target_home/.oh-my-zsh/custom"
        if ensure_cmd git git "required for plugin install"; then
            [[ -d "$custom_dir/plugins/zsh-autosuggestions" ]] || run_as_user "$target_user" "git clone https://github.com/zsh-users/zsh-autosuggestions \"$custom_dir/plugins/zsh-autosuggestions\"" >/dev/null 2>&1 || true
            [[ -d "$custom_dir/plugins/zsh-syntax-highlighting" ]] || run_as_user "$target_user" "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \"$custom_dir/plugins/zsh-syntax-highlighting\"" >/dev/null 2>&1 || true
        fi
    fi

    # Create .zshrc (only if oh-my-zsh exists)
    if [[ -d "$target_home/.oh-my-zsh" ]]; then
        if [[ ! -f "$target_home/.zshrc" ]]; then
            tee "$target_home/.zshrc" > /dev/null << 'EOF'
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set theme
ZSH_THEME="agnoster"

# Plugins
plugins=(
    git
    sudo
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# User configuration
export EDITOR="nano"
export LANG=en_US.UTF-8

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias c='clear'
alias h='history'
alias zsh-reload='source ~/.zshrc'

# Better history
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt SHARE_HISTORY
EOF
            if [[ "$target_user" != "root" ]]; then
                chown "$target_user:$target_user" "$target_home/.zshrc" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if ask_confirm "Set zsh as the default shell for $target_user?"; then
        if chsh -s "$(which zsh)" "$target_user"; then
            changed_shell=true
        else
            warn "Failed to change shell for $target_user (continuing)."
        fi
    fi

    if [[ "$changed_shell" == true || -d "$target_home/.oh-my-zsh" ]]; then
        success "Zsh configured for $target_user."
    else
        warn "Zsh installed but not fully configured for $target_user."
    fi
}

step_update_packages() {
    info "Step 1: Packages & Dependencies"
    if ! ask_confirm "Update packages and optionally install dependencies?"; then
        warn "Skipping system update."
        return 0
    fi

    if ask_confirm "Run system update (apt update + full-upgrade)?" "Y"; then
        info "Updating package lists..."
        apt update
        APT_UPDATED=true
        info "Upgrading packages..."
        DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
    fi

    if ask_confirm "Install base dependencies (curl, git, zsh, build tools, etc.)?"; then
        # Ensure package lists are present (user may have skipped apt update above).
        [[ "${APT_UPDATED:-false}" == "true" ]] || apt_update_once || true
        info "Installing base dependencies..."
        apt install -y curl git software-properties-common unzip zip wget tree zsh sudo build-essential
    fi

    if ask_confirm "Cleanup unused packages (autoremove/autoclean)?"; then
        info "Cleaning up..."
        apt autoremove -y
        apt autoclean
    fi
}

step_zsh_root() {
    info "Step 2: Zsh for Root"
    if ask_confirm "Configure Zsh (Oh My Zsh) for root?"; then
        setup_zsh_for_user "root"
    fi
}

step_create_user() {
    info "Step 3: Create Sudo User"

    NEW_USER=""
    if ! ask_confirm "Create a new sudo user?"; then
        return 0
    fi

    read -r -p "Enter username: " NEW_USER
    NEW_USER="${NEW_USER#"${NEW_USER%%[![:space:]]*}"}"
    NEW_USER="${NEW_USER%"${NEW_USER##*[![:space:]]}"}"
    if [[ -z "$NEW_USER" ]]; then
        warn "Username cannot be empty. Skipping user creation."
        return 0
    fi
    if id "$NEW_USER" &>/dev/null; then
        warn "User $NEW_USER already exists."
        return 0
    fi

    read -r -s -p "Enter password for $NEW_USER: " USER_PASS
    echo ""

    local shell="/bin/bash"
    if command_exists zsh && ask_confirm "Use zsh as default shell for $NEW_USER?" "Y"; then
        shell="$(which zsh)"
    fi

    useradd -m -s "$shell" -G sudo "$NEW_USER"
    echo "$NEW_USER:$USER_PASS" | chpasswd
    success "User $NEW_USER created and added to sudo group."

    if ask_confirm "Setup Zsh (Oh My Zsh) for $NEW_USER?"; then
        setup_zsh_for_user "$NEW_USER"
    fi
}

step_swap() {
    info "Step 4: Swap"
    if ! ask_confirm "Add swap memory?"; then
        return 0
    fi

    if ! ensure_cmd mkswap util-linux "swap setup tool"; then
        warn "Skipping swap setup."
        return 0
    fi
    if ! ensure_cmd swapon util-linux "swap setup tool"; then
        warn "Skipping swap setup."
        return 0
    fi

    read -r -p "Enter swap size in GiB (integer, e.g., 2): " SWAP_GIB
    if [[ ! "$SWAP_GIB" =~ ^[0-9]+$ ]] || [[ "$SWAP_GIB" -le 0 ]]; then
        warn "Invalid swap size: '$SWAP_GIB' (expected a positive integer GiB). Skipping."
        return 0
    fi

    local swap_size="${SWAP_GIB}G"
    local swap_mib=$(( SWAP_GIB * 1024 ))

    if swapon --show=NAME 2>/dev/null | grep -Fxq "/swapfile"; then
        warn "Swapfile is already active. Skipping."
        return 0
    fi
    if [[ -f /swapfile ]]; then
        warn "Swapfile already exists. Skipping."
        return 0
    fi

    info "Creating $swap_size swapfile..."
    if command_exists fallocate && ask_confirm "Use fallocate for swapfile creation (fast)?" "Y"; then
        if ! fallocate -l "$swap_size" /swapfile; then
            warn "fallocate failed; falling back to dd."
            dd if=/dev/zero of=/swapfile bs=1M count="$swap_mib" status=progress
        fi
    else
        dd if=/dev/zero of=/swapfile bs=1M count="$swap_mib" status=progress
    fi

    chmod 600 /swapfile
    mkswap /swapfile
    if ! swapon /swapfile; then
        warn "swapon failed (often happens in containers or restricted environments)."
        warn "Swapfile was created at /swapfile but NOT activated."
        if ask_confirm "Remove /swapfile now?" "Y"; then
            rm -f /swapfile || warn "Failed to remove /swapfile (continuing)."
        fi
        return 0
    fi

    append_line_if_missing '/swapfile none swap sw 0 0' /etc/fstab

    if ask_confirm "Set vm.swappiness=10 (recommended for many servers)?" "Y"; then
        sysctl vm.swappiness=10
        append_line_if_missing 'vm.swappiness=10' /etc/sysctl.conf
    fi

    success "Swap enabled ($swap_size)."
}

step_ufw() {
    info "Step 5: Firewall (UFW)"
    if ! ask_confirm "Install and configure UFW (Uncomplicated Firewall)?"; then
        return 0
    fi

    if ! ensure_cmd ufw ufw "firewall"; then
        warn "Skipping UFW setup."
        return 0
    fi

    # UFW uses iptables/nftables under the hood. In restricted environments (e.g., containers),
    # commands may exist but still fail with "Permission denied".
    if ! ufw status >/dev/null 2>&1; then
        warn "UFW cannot query/apply firewall rules in this environment (iptables/nft permission issue)."
        warn "Skipping UFW configuration."
        return 0
    fi

    if ask_confirm "Set UFW defaults (deny incoming + allow outgoing)?" "Y"; then
        ufw default deny incoming || { warn "Failed to apply UFW default deny incoming."; return 0; }
        ufw default allow outgoing || { warn "Failed to apply UFW default allow outgoing."; return 0; }
    fi

    if ask_confirm "Allow SSH (port 22) through UFW?" "Y"; then
        ufw allow ssh || { warn "Failed to allow SSH in UFW."; return 0; }
    fi

    if ask_confirm "Allow HTTP (80) and HTTPS (443) through UFW?" "Y"; then
        ufw allow 80/tcp || { warn "Failed to allow HTTP (80) in UFW."; return 0; }
        ufw allow 443/tcp || { warn "Failed to allow HTTPS (443) in UFW."; return 0; }
    fi

    if ask_confirm "Enable UFW now?" "Y"; then
        echo "y" | ufw enable || { warn "Failed to enable UFW."; return 0; }
        success "UFW enabled."
    else
        warn "UFW enable skipped."
        success "UFW rules applied (not enabled)."
    fi
}

step_fail2ban() {
    info "Step 6: Fail2Ban"
    if ! ask_confirm "Install Fail2Ban for SSH protection?"; then
        return 0
    fi

    if ! ensure_cmd fail2ban-client fail2ban "SSH brute-force protection"; then
        warn "Skipping Fail2Ban."
        return 0
    fi

    local enabled_on_boot=false
    local started=false

    if command_exists systemctl; then
        if ask_confirm "Enable Fail2Ban to start on boot?"; then
            if systemctl enable fail2ban 2>/dev/null; then
                enabled_on_boot=true
            else
                warn "Failed to enable Fail2Ban (continuing)."
            fi
        fi
        if ask_confirm "Start Fail2Ban now?"; then
            if systemctl start fail2ban 2>/dev/null; then
                started=true
            else
                warn "Failed to start Fail2Ban (continuing)."
            fi
        fi
    else
        warn "systemctl not available; cannot enable Fail2Ban on boot automatically."
        if ask_confirm "Try to start Fail2Ban using service now?" "Y"; then
            if service fail2ban start 2>/dev/null || service fail2ban restart 2>/dev/null; then
                started=true
            else
                warn "Failed to start Fail2Ban (continuing)."
            fi
        fi
    fi

    if [[ "$enabled_on_boot" == true || "$started" == true ]]; then
        if [[ "$started" == true ]]; then
            success "Fail2Ban started."
        elif [[ "$enabled_on_boot" == true ]]; then
            success "Fail2Ban enabled on boot."
        fi
    else
        warn "Fail2Ban installed, but was not enabled/started."
    fi
}

step_ssh_keys_and_hardening() {
    info "Step 7: SSH Keys & Hardening"
    if ! ask_confirm "Setup SSH keys and implement security hardening?"; then
        return 0
    fi

    local provided_pub_key=""
    if ask_confirm "Provide an existing public key for SSH login (recommended)?" "Y"; then
        echo -e "${YELLOW}Paste your public key (starts with ssh-rsa, ssh-ed25519, etc.) and press Enter:${NC}"
        read -r provided_pub_key
    fi

    if [[ -n "$provided_pub_key" ]]; then
        if ask_confirm "Add provided public key to root's authorized_keys?" "Y"; then
            mkdir -p /root/.ssh
            chmod 700 /root/.ssh
            echo "$provided_pub_key" >> /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            info "Public key added to root's authorized_keys."
        fi
    fi

    if [[ -n "$NEW_USER" ]]; then
        local user_home="/home/$NEW_USER"
        mkdir -p "$user_home/.ssh"
        chmod 700 "$user_home/.ssh"
        chown -R "$NEW_USER:$NEW_USER" "$user_home/.ssh" || true

        if [[ -n "$provided_pub_key" ]]; then
            if ask_confirm "Add provided public key to $NEW_USER's authorized_keys?" "Y"; then
                echo "$provided_pub_key" >> "$user_home/.ssh/authorized_keys"
                chmod 600 "$user_home/.ssh/authorized_keys"
                chown "$NEW_USER:$NEW_USER" "$user_home/.ssh/authorized_keys" || true
                info "Public key added to $NEW_USER's authorized_keys."
            fi
        fi

        if ask_confirm "Generate a new ED25519 SSH key for $NEW_USER (useful for Git deploy keys)?" "N"; then
            if ensure_cmd ssh-keygen openssh-client "SSH key generation"; then
                if [[ ! -f "$user_home/.ssh/id_ed25519" ]]; then
                    run_as_user "$NEW_USER" "ssh-keygen -t ed25519 -f \"$user_home/.ssh/id_ed25519\" -N \"\""
                    info "New SSH key generated for $NEW_USER."
                    info "Public key:"
                    cat "$user_home/.ssh/id_ed25519.pub"
                else
                    warn "SSH key already exists for $NEW_USER."
                fi
            else
                warn "Skipping key generation (ssh-keygen unavailable)."
            fi
        fi
    fi

    if ask_confirm "Harden SSH server config (disable root login and password auth)?" "Y"; then
        local sshd_config="/etc/ssh/sshd_config"

        if [[ ! -f "$sshd_config" ]]; then
            warn "OpenSSH server config not found at $sshd_config."
            if ensure_pkg openssh-server "provides sshd + sshd_config"; then
                true
            fi
        fi

        if [[ ! -f "$sshd_config" ]]; then
            warn "Skipping SSH hardening (sshd_config still not found)."
            return 0
        fi

        if ask_confirm "Backup SSH config to ${sshd_config}.bak?" "Y"; then
            cp "$sshd_config" "${sshd_config}.bak" || warn "Failed to backup $sshd_config (continuing)."
        fi

        if ask_confirm "Apply: PermitRootLogin no, PasswordAuthentication no, PubkeyAuthentication yes?" "Y"; then
            # PermitRootLogin
            if grep -qE '^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+' "$sshd_config"; then
                sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
            else
                echo "PermitRootLogin no" >> "$sshd_config"
            fi

            # PasswordAuthentication
            if grep -qE '^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+' "$sshd_config"; then
                sed -i 's/^[[:space:]]*#\?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
            else
                echo "PasswordAuthentication no" >> "$sshd_config"
            fi

            # PubkeyAuthentication
            if grep -qE '^[[:space:]]*#?[[:space:]]*PubkeyAuthentication[[:space:]]+' "$sshd_config"; then
                sed -i 's/^[[:space:]]*#\?[[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
            else
                echo "PubkeyAuthentication yes" >> "$sshd_config"
            fi
        else
            warn "Skipping SSH hardening config edits."
        fi

        if ask_confirm "Restart SSH service now to apply changes?" "Y"; then
            if restart_ssh_service; then
                success "SSH hardening applied."
            else
                warn "SSH config updated, but could not restart SSH service automatically."
                warn "Restart manually when convenient (e.g. 'systemctl restart ssh' or 'systemctl restart sshd')."
            fi
        else
            warn "SSH service restart skipped. Changes will apply on next restart."
        fi
    fi

    success "SSH step finished."
}

main() {
    require_root
    detect_os

    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        error "Unsupported OS: $OS. This script requires a Debian or Ubuntu based system."
        exit 1
    fi

    print_banner

    step_update_packages
    step_zsh_root
    step_create_user
    step_swap
    step_ufw
    step_fail2ban
    step_ssh_keys_and_hardening

    echo ""
    success "Genie server bootstrapping complete!"
    if [[ -n "${NEW_USER:-}" ]]; then
        info "You can now login as: $NEW_USER"
    fi
    warn "Please remember to test your SSH connection in a NEW terminal before closing this one!"
    echo ""
}

main
