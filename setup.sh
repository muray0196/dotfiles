# Notify the user about starting the setup script
echo "Starting setup.sh with elevated privileges..."
sudo -v

# Update and upgrade the system
echo "Updating and upgrading system packages..."
sudo apt update && sudo apt upgrade -y

# Install Zsh and set it as the default shell
echo "Installing Zsh and switching to it as the default shell..."
sudo apt install zsh -y
chsh -s /usr/bin/zsh

# Install necessary development tools and Homebrew
echo "Installing development tools and Homebrew..."
sudo apt install build-essential procps curl file git -y
yes | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Update and upgrade Homebrew
echo "Updating and upgrading Homebrew packages..."
brew update && brew upgrade

# Install essential tools via Homebrew
echo "Installing essential tools via Homebrew..."
brew install starship sheldon fzf ripgrep fastfetch neovim uv

# Configure Git
echo "Configuring Git with user details..."
git config --global user.name "muray0196"
git config --global user.email "howmuch2733@gmail.com"
mkdir .ssh
cd .ssh
ssh-keygen -t rsa

# Setup Zsh configuration
echo "Setting up Zsh configuration..."
cat << 'EOF' > ~/.zshrc
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
alias update='sudo apt update && sudo apt upgrade && brew update && brew upgrade'
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
alias vi='nvim'

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
    BUFFER=$(history -n 1 | awk '!seen[$0]++' | fzf --reverse --height 40% --query $BUFFER)
    CURSOR=$#BUFFER
    zle reset-prompt
}
zle -N fzf-history-selection

# Loading time
zsh_end_time=$(date +%s%N)
echo ".zshrc loading time: $(( (zsh_end_time - zsh_start_time) / 1000000 )) ms"
EOF

# Setup Sheldon configuration
echo "Setting up Sheldon configuration..."
mkdir -p ~/.config/sheldon
cat << 'EOF' > ~/.config/sheldon/plugins.toml
shell = "zsh"

[plugins]
[plugins.zsh-defer]
github = "romkatv/zsh-defer"

[plugins.zsh-abbr]
github = "olets/zsh-abbr"

[plugins.zsh-autosuggestions]
github = "zsh-users/zsh-autosuggestions"
apply = ["defer"]

[plugins.zsh-syntax-highlighting]
github = "romkatv/zsh-syntax-highlighting"
apply = ["defer"]

[templates]
defer = "{{ hooks?.pre | nl }}{% for file in files %}zsh-defer source \"{{ file }}\"\n{% endfor %}{{ hooks?.post | nl }}"
EOF

# Setup Neovim configuration
echo "Setting up Neovim configuration..."
mkdir -p ~/.config/nvim
cat << 'EOF' > ~/.config/nvim/init.lua
-- Basic Settings
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Appearance Settings
vim.opt.laststatus = 2
vim.opt.cursorline = true

-- Key Mappings
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Esc><Esc>", ":nohl<CR>", { noremap = true, silent = true })

-- Miscellaneous
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
EOF

# Setup Zsh-Abbr configuration
echo "Setting up Zsh-Abbr configuration..."
mkdir -p ~/.config/zsh-abbr
cat << 'EOF' > ~/.config/zsh-abbr/user-abbreviations
abbr "update"="sudo apt update && sudo apt upgrade && brew update && brew upgrade"
abbr ".."="cd .."
abbr "ll"="ls -alF"
abbr "la"="ls -a"
abbr "l"="ls -CF"
abbr "gs"="git status"
abbr "ga"="git add"
abbr "gc"="git commit"
abbr "gp"="git push"
abbr "gpl"="git pull"
abbr "gl"="git log --oneline --graph --all"
abbr "act"="source .venv/bin/activate"
abbr "vi"="nvim"
EOF

# Setup Fastfetch configuration
echo "Setting up Fastfetch configuration..."
mkdir -p ~/.config/fastfetch
cat << 'EOF' > ~/.config/fastfetch/config.jsonc
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": "ubuntu_old2_small",
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "packages",
    "shell",
    "de",
    "wm",
    "wmtheme",
    "theme",
    "icons",
    "font",
    "terminal",
    "memory",
    "localip",
    "locale",
    "break",
  ]
}
EOF

# Setup Starship configuration
echo "Setting up Starship configuration..."
cat << 'EOF' > ~/.config/starship.toml
format = """
[░▒▓](#4a557e)\
[ 󰕈](bg:#4a557e fg:#fa8050)\
$username\
[](bg:#bd93f9 fg:#4a557e)\
$directory\
[](fg:#bd93f9 bg:#3a1b3d)\
$git_branch\
$git_status\
[](fg:#3a1b3d bg:#281026)\
$python\
$nodejs\
$rust\
$golang\
$php\
[](fg:#281026 bg:#16001a)\
$docker_context\
$conda\
[](fg:#16001a)\
\n$character
"""

[username]
show_always = true
style_user = "bg:#4a557e fg:#f8f8f2"
style_root = "bg:#4a557e fg:#ff5555"
format = '[ $user ]($style)'

[directory]
style = "fg:#f8f8f2 bg:#bd93f9"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = ""
style = "bg:#3a1b3d"
format = '[[ $symbol $branch ](fg:#bd93f9 bg:#3a1b3d)]($style)'

[git_status]
style = "bg:#3a1b3d"
format = '[[($all_status$ahead_behind )](fg:#bd93f9 bg:#3a1b3d)]($style)'

[python]
symbol = ""
style = "bg:#281026"
format = '[[ $symbol ($version)(\($virtualenv\)) ](fg:#bd93f9 bg:#281026)]($style)'

[nodejs]
symbol = ""
style = "bg:#281026"
format = '[[ $symbol ($version) ](fg:#bd93f9 bg:#281026)]($style)'

[rust]
symbol = ""
style = "bg:#281026"
format = '[[ $symbol ($version) ](fg:#bd93f9 bg:#281026)]($style)'

[golang]
symbol = ""
style = "bg:#281026"
format = '[[ $symbol ($version) ](fg:#bd93f9 bg:#281026)]($style)'

[php]
symbol = ""
style = "bg:#281026"
format = '[[ $symbol ($version) ](fg:#bd93f9 bg:#281026)]($style)'

[docker_context]
symbol = ""
style = "bg:#16001a"
format = '[[ $symbol ($context) ](fg:#8be9fd bg:#16001a)]($style)'

[conda]
style = "bg:#16001a"
format = '[[ $symbol ($environment) ](fg:#8be9fd bg:#16001a)]($style)'

[character]
disabled = false
success_symbol = '[\$](fg:#f8f8f2)'
error_symbol = '[\$](fg:#ff5555)'
EOF

# Setup complete
echo "Setup completed successfully."