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

    if ! command -v brew &> /dev/null; then
        echo "Homebrew is required. Install it first, then rerun this script."
        exit 1
    fi
    brew install age chezmoi

elif [ "$OS" = "Linux" ]; then
    echo "🔧 Installing system dependencies..."
    sudo apt update
    sudo apt install -y curl age build-essential procps file

    if ! command -v brew &> /dev/null; then
        echo "Homebrew is required. Install it first, then rerun this script."
        exit 1
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
