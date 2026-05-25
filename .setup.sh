#!/bin/bash
set -eufo pipefail

OS="$(uname -s)"

echo "🚀 Setting up dotfiles..."

if [ "$OS" = "Darwin" ]; then
    # --- macOS ---
    if xcode-select -p &> /dev/null; then
        echo "✅ Xcode CLI tools already installed."
    else
        echo "🔧 Installing Xcode CLI tools..."
        xcode-select --install &> /dev/null
        while ! xcode-select -p &> /dev/null; do sleep 5; done
        echo "✅ Xcode CLI tools installed."
    fi

    if which -s brew; then
        echo "✅ Homebrew already installed."
    else
        echo "🍺 Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c \
          "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    brew install chezmoi age 1password-cli

elif [ "$OS" = "Linux" ]; then
    # --- Linux (Debian/Ubuntu) ---
    sudo apt update
    sudo apt install -y curl git age
    sh -c "$(curl -fsLS get.chezmoi.io)"

    # Install 1Password CLI
    # (Follow https://developer.1password.com/docs/cli/get-started/#install for latest)
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
      sudo tee /etc/apt/sources.list.d/1password.list
    sudo apt update && sudo apt install -y 1password-cli
fi

echo ""
echo "🔐 Please sign into 1Password CLI now:"
eval "$(op signin < /dev/tty)"

if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
    echo "ℹ️  Already initialized. Pulling latest..."
    chezmoi update < /dev/tty
else
    chezmoi init satyvm/dot < /dev/tty
fi

echo "✅ Done!"