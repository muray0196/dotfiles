zsh_start_time=$(date +%s%N)

# Environment Setup
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
eval "$(starship init zsh)"
eval "$(sheldon source)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Keybindings
bindkey '^@' autosuggest-accept
bindkey '^r' fzf-history-selection

# Aliases
alias update='sudo apt update && sudo apt upgrade -y && brew update && brew upgrade'
alias ..='cd ..'
alias ll='ls -alF'
alias la='ls -a'
alias l='ls -CF'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline --graph --all'
alias act='source .venv/bin/activate'
alias deact='deactivate'
alias nv='nvim'

# Completion Settings
autoload -Uz compinit
zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -e $zcompdump ]]; then
    zmodload zsh/complist
    compinit -d -C
else
    compinit -C
fi
zstyle ':completion:*' menu select
zstyle ':completion:*' scroll true
zstyle ':completion:*' format '%F{yellow}%d%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
compaudit | xargs chmod g-w,o-w 2>/dev/null

# History Settings
setopt histignorealldups sharehistory
HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history

# fzf History
function fzf-history-selection() {
    local query="$BUFFER"
    BUFFER=$(history -n 1 | awk '!seen[$0]++' | fzf --reverse --height 40% --query "$query")
    CURSOR=$#BUFFER
    zle reset-prompt
}
zle -N fzf-history-selection

# Loading time
zsh_end_time=$(date +%s%N)
echo ".zshrc loading time: $(( (zsh_end_time - zsh_start_time) / 1000000 )) ms"
