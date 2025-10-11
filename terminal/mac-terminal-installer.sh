#!/bin/bash
set -e

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo ""
echo "🍺 Starting Homebrew and Zsh installation on macOS..."
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is designed for macOS only."
    exit 1
fi

# Setup hostname
echo "💻 Current hostname: $(scutil --get ComputerName 2>/dev/null || echo "Not set")"
read -rp "🔧 Enter new hostname (or press Enter to skip): " new_hostname

if [[ -n "$new_hostname" ]]; then
    echo "🔄 Setting hostname to '$new_hostname'..."
    echo "🔐 This requires admin privileges..."
    sudo scutil --set ComputerName "$new_hostname"
    sudo scutil --set HostName "$new_hostname"
    sudo scutil --set LocalHostName "$new_hostname"
    sudo dscacheutil -flushcache
    echo "✅ Hostname set to '$new_hostname'"
else
    echo "⏭️  Skipping hostname change"
fi

echo ""

# Install Homebrew if not already installed
if command_exists brew; then
    echo "✅ Homebrew is already installed."
    echo "📦 Updating Homebrew..."
    brew update
else
    echo "🔄 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "🔧 Adding Homebrew to PATH for Apple Silicon..."
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo "🔧 Adding Homebrew to PATH for Intel Mac..."
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

echo ""

# Install iTerm2 if not already installed
if [[ -d "/Applications/iTerm.app" ]]; then
    echo "✅ iTerm2 is already installed."
else
    echo "🖥️  Installing iTerm2..."
    brew install --cask iterm2
    echo "✅ iTerm2 installed successfully!"
    echo "💡 You can switch to iTerm2 for a better terminal experience."
fi

echo ""

# Install Zsh if not already installed
if command_exists zsh; then
    echo "✅ Zsh is already installed."
    zsh --version
else
    echo "🔄 Installing Zsh via Homebrew..."
    brew install zsh
fi

echo ""

# Check if Zsh is the default shell
current_shell="$SHELL"
if [[ "$current_shell" == *"zsh"* ]]; then
    echo "✅ Zsh is already your default shell."
else
    echo "🔄 Setting Zsh as default shell..."
    
    # Get the path to the Homebrew-installed zsh
    zsh_path="$(brew --prefix)/bin/zsh"
    
    # Add to /etc/shells if not already there
    if ! grep -q "$zsh_path" /etc/shells; then
        echo "🔐 Adding $zsh_path to /etc/shells (requires admin password)..."
        echo "$zsh_path" | sudo tee -a /etc/shells
    fi
    
    # Change default shell
    echo "🔐 Changing default shell to Zsh (requires admin password)..."
    chsh -s "$zsh_path"
fi

# Install Oh My Zsh
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "✅ Oh My Zsh is already installed."
else
    echo "🎨 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Powerlevel10k theme
echo "⚡ Installing Powerlevel10k theme..."
if [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]]; then
    echo "✅ Powerlevel10k is already installed."
    cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    git pull --quiet 2>/dev/null || echo "⚠️  Could not update Powerlevel10k"
    cd - > /dev/null
else
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
fi

# Install required fonts for Powerlevel10k and programming ligatures
echo "🔤 Installing Nerd Fonts with ligature support..."
brew install --cask font-fira-code-nerd-font
brew install --cask font-jetbrains-mono-nerd-font
brew install --cask font-hack-nerd-font
brew install --cask font-sauce-code-pro-nerd-font
brew install --cask font-caskaydia-cove-nerd-font
brew install --cask font-inconsolata-nerd-font
brew install --cask font-meslo-lg-nerd-font

# Install zsh plugins
echo "🔌 Installing Zsh plugins..."

# Install zsh-autosuggestions
AUTOSUGGESTIONS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
if [[ -d "$AUTOSUGGESTIONS_DIR" ]]; then
    echo "✅ zsh-autosuggestions is already installed."
    cd "$AUTOSUGGESTIONS_DIR"
    git pull --quiet 2>/dev/null || echo "⚠️  Could not update zsh-autosuggestions"
    cd - > /dev/null
else
    git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_DIR"
fi

# Install zsh-syntax-highlighting
SYNTAX_HIGHLIGHTING_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
if [[ -d "$SYNTAX_HIGHLIGHTING_DIR" ]]; then
    echo "✅ zsh-syntax-highlighting is already installed."
    cd "$SYNTAX_HIGHLIGHTING_DIR"
    git pull --quiet 2>/dev/null || echo "⚠️  Could not update zsh-syntax-highlighting"
    cd - > /dev/null
else
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHTING_DIR"
fi

# Install useful command-line tools
echo "🛠️  Installing useful CLI tools..."
brew install wget tree bat eza fd ripgrep fzf

# Install fzf shell integration
echo "🔍 Setting up fzf shell integration..."
"$(brew --prefix)"/opt/fzf/install --all --no-bash --no-fish --no-update-rc

echo ""

# Optional: Install zeitfetch (modern system information tool written in Rust)
read -rp "📊 Would you like to install zeitfetch (fast system info display tool)? (y/N): " install_zeitfetch
if [[ "$install_zeitfetch" =~ ^[Yy]$ ]]; then
    echo "🔄 Installing zeitfetch via Homebrew..."
    brew tap nidnogg/zeitfetch
    brew install zeitfetch
    echo "✅ zeitfetch installed! Run 'zeitfetch' to see your system info."
    
    # Ask if they want to run it on shell startup
    read -rp "🚀 Would you like zeitfetch to run automatically on terminal startup? (y/N): " run_on_startup
    if [[ "$run_on_startup" =~ ^[Yy]$ ]]; then
        ZEITFETCH_ON_STARTUP=true
    else
        ZEITFETCH_ON_STARTUP=false
    fi
else
    echo "⏭️  Skipping zeitfetch installation"
fi

# Create custom .zshrc configuration
echo "📝 Creating custom .zshrc configuration..."

# Backup existing .zshrc if it exists
if [[ -f "$HOME/.zshrc" ]]; then
    echo "📋 Backing up existing .zshrc to .zshrc.backup"
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

# Create new .zshrc with custom configuration
cat > "$HOME/.zshrc" << 'EOF'
unsetopt nomatch

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Homebrew PATH setup
if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# User configuration
export TERM="xterm-256color"
export SHELL="/bin/zsh"
export EDITOR="nano"
export LANG=en_US.UTF-8
export ARCHFLAGS="-arch x86_64"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# use case-sensitive completion.
CASE_SENSITIVE="true"

# display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# command execution time stamp shown in the history command output.
HIST_STAMPS="dd.mm.yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
plugins=(
    git
    brew
    macos
    colored-man-pages
    command-not-found
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Better history configuration
export HISTSIZE=100000
export SAVEHIST=100000
export HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# Zsh autosuggestions configuration
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#666666"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Better completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors ''
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias grep='grep --color=auto'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias c='clear'
alias h='history'

alias zsh-edit='nano ~/.zshrc'
alias zsh-reload='source ~/.zshrc'

alias brew-up='brew update && brew upgrade && brew cleanup'
alias git-cleanup='git branch | grep -v "^\s*\*|\bmain\b|\bmaster\b|\bdevelop\b|\bdev\b" | xargs -r git branch -d'

# Modern CLI tool aliases (if installed)
command -v eza >/dev/null && alias ls='eza --icons' && alias ll='eza -la --icons'
command -v bat >/dev/null && alias cat='bat'
command -v fd >/dev/null && alias find='fd'
command -v rg >/dev/null && alias grep='rg'

# FZF configuration
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Load fzf shell integration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
EOF

# Add zeitfetch to .zshrc if user wants it on startup
if [[ "${ZEITFETCH_ON_STARTUP:-false}" == "true" ]]; then
    {
        echo ""
        echo "# Display system information on startup"
        echo "command -v zeitfetch >/dev/null && zeitfetch"
    } >> "$HOME/.zshrc"
    echo "✅ Added zeitfetch to run on terminal startup"
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "🔄 Please restart your terminal or run 'exec zsh' to start using your new setup."
echo "⚡ Run 'p10k configure' to customize your Powerlevel10k prompt."