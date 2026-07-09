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
    echo "🔧 Installing system dependencies..."
    sudo apt update
    sudo apt install -y curl git age build-essential procps file

    # 🍺 Install Homebrew if not already installed
    if [ ! -d "/home/linuxbrew/.linuxbrew" ] && ! command -v brew &> /dev/null; then
        echo "🍺 Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Activate Linuxbrew environment for this script run
    if [ -d "/home/linuxbrew/.linuxbrew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # Ensure ~/.local/bin exists and is on the PATH
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    # Install chezmoi if not already installed
    if ! command -v chezmoi &> /dev/null; then
        echo "🔧 Installing chezmoi..."
        if command -v brew &> /dev/null; then
            brew install chezmoi
        else
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        fi
    fi
fi

if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
    echo "ℹ️  Already initialized. Pulling latest..."
    chezmoi update
else
    chezmoi init --apply satyvm/dot
fi

echo "✅ Done!"
