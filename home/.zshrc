# =============================================================================
# ~/.zshrc — managed by satyvm/dot
# =============================================================================

# ── Homebrew ──────────────────────────────────────────────────────────────────
if [[ "$(uname -m)" == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# ── Path ──────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export PATH="$PATH:$HOME/.foundry/bin"        # Foundry (Solidity)

# ── Colima (Docker runtime — headless, no UI) ─────────────────────────────────
# Docker CLI talks to Colima via its socket
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"

# ── SSH agent ─────────────────────────────────────────────────────────────────
# Use 1Password SSH agent socket if the app is running, else fall back to local
OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ -S "$OP_SOCK" ]]; then
  export SSH_AUTH_SOCK="$OP_SOCK"
elif [[ -S "$HOME/.1password/agent.sock" ]]; then
  export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
else
  # Fall back: start a local ssh-agent and load any local keys
  if ! pgrep -u "$USER" ssh-agent &>/dev/null; then
    eval "$(ssh-agent -s)" &>/dev/null
  fi
  for key in "$HOME/.ssh"/id_ed25519_*; do
    [[ -f "$key" && "${key##*.}" != "pub" ]] && ssh-add "$key" &>/dev/null || true
  done
fi

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY          # share across sessions
setopt HIST_IGNORE_DUPS       # no duplicate entries
setopt HIST_IGNORE_SPACE      # ignore commands starting with space
setopt EXTENDED_HISTORY       # timestamp in history

# ── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit
compinit -i

# ── Plugins ───────────────────────────────────────────────────────────────────
# zsh-autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=244"
[[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting (must be last)
[[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ── fzf ───────────────────────────────────────────────────────────────────────
[[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ]] && \
  source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
[[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]] && \
  source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# ── zoxide (smart cd) ─────────────────────────────────────────────────────────
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"

# ── Aliases ───────────────────────────────────────────────────────────────────
# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Modern replacements
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --icons --level=2'
alias cat='bat --style=plain'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gbr='git branch'

# Kubernetes
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'

# Editing
alias v='nvim'
alias vi='nvim'

# Utilities
alias reload='source ~/.zshrc'
alias ip='curl -s ifconfig.me'
alias ports='lsof -i -n -P | grep LISTEN'
alias dot='cd ~/Developer/personal/dot'

# ── Editor ────────────────────────────────────────────────────────────────────
export EDITOR='nvim'
export VISUAL='nvim'

# ── Language settings ─────────────────────────────────────────────────────────
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# ── Starship prompt ───────────────────────────────────────────────────────────
command -v starship &>/dev/null && eval "$(starship init zsh)"
