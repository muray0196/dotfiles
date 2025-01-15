# Notify the user about starting the setup script
sudo -v

# Update and upgrade the system
sudo apt update
sudo apt upgrade -y

# Install Zsh and set it as the default shell
sudo apt install zsh -y
chsh -s /usr/bin/zsh

# Install necessary development tools and Homebrew
sudo apt install build-essential procps curl file git -y
yes | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Update and upgrade Homebrew
brew update && brew upgrade

# Install essential tools via Homebrew
brew install starship sheldon fzf ripgrep fastfetch neovim uv

# Configure Git
git config --global user.name "muray0196"
git config --global user.email "howmuch2733@gmail.com"
mkdir .ssh
cd .ssh
ssh-keygen -t rsa

# Create symbolic links for configuration files
mkdir -p ~/.config/

ln -sf ~/dotfiles/.config/zsh/.zshrc ~/.zshrc
ln -sf ~/dotfiles/.config/zsh/.zshprofile ~/.zshprofile
ln -sf ~/dotfiles/.config/starship/starship.toml ~/.config/starship.toml
ln -sf ~/dotfiles/.config/zsh/zsh-abbr ~/.config
ln -sf ~/dotfiles/.config/nvim ~/.config
ln -sf ~/dotfiles/.config/sheldon ~/.config
ln -sf ~/dotfiles/.config/fastfetch ~/.config

# Setup complete
echo "Setup completed successfully.