# User-local executables take precedence.
export PATH="$HOME/.local/bin:$PATH"

# Homebrew is optional. Support the standard Linux location and a user-local one.
if (( ! $+commands[brew] )); then
  for _brew in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [[ -x "$_brew" ]]; then
      eval "$("$_brew" shellenv)"
      break
    fi
  done
fi
unset _brew

# Development runtimes are optional and managed by mise.
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

# Completion.
autoload -Uz compinit
zmodload zsh/complist
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -s "$_zcompdump" ]]; then
  compinit -d "$_zcompdump" -C
else
  compinit -d "$_zcompdump"
fi
unset _zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' format '%F{yellow}%d%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes

# History.
setopt hist_ignore_all_dups share_history
HISTSIZE=5000
SAVEHIST=5000
HISTFILE="$HOME/.zsh_history"

# Prompt and plugins are guarded so the shell still starts during bootstrap.
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

if (( $+commands[sheldon] )); then
  eval "$(sheldon source)"
fi

if (( $+commands[abbr] || $+functions[abbr] )); then
  # Optional profile-specific abbreviation files are regular Zsh snippets.
  for _abbr_file in "$HOME"/.config/zsh-abbr/extra/*.zsh(N); do
    source "$_abbr_file"
  done
  unset _abbr_file
  eval "$(abbr export-aliases)"
fi

# Accept the current autosuggestion with Ctrl-Space when the plugin loaded.
if (( $+widgets[autosuggest-accept] )); then
  bindkey '^@' autosuggest-accept
fi

# Lightweight fzf history search. It is enabled only when fzf exists.
if (( $+commands[fzf] )); then
  fzf-history-selection() {
    local query="$BUFFER"
    local selection
    selection="$(history -n 1 | awk '!seen[$0]++' | fzf --reverse --height 40% --query "$query")" || return
    BUFFER="$selection"
    CURSOR=${#BUFFER}
    zle reset-prompt
  }
  zle -N fzf-history-selection
  bindkey '^R' fzf-history-selection
fi

# Machine-local settings are deliberately outside Git.
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
export PATH="$HOME/.local/share/npm/bin:$PATH"
