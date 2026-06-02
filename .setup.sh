#!/bin/bash
set -eufo pipefail

OS="$(uname -s)"

echo "🚀 Setting up dotfiles..."

if [ "$OS" = "Darwin" ]; then
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
        /bin/bash -c \
          "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    brew install age chezmoi

elif [ "$OS" = "Linux" ]; then
    sudo apt update
    sudo apt install -y curl git age
    sh -c "$(curl -fsLS get.chezmoi.io)"
fi

if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
    echo "ℹ️  Already initialized. Pulling latest..."
    chezmoi update
else
    chezmoi init --apply satyvm/dot
fi

echo "✅ Done!"
