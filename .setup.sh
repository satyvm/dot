#!/bin/bash
set -euf
(set -o pipefail 2>/dev/null) && set -o pipefail || true

# Ensure standard Homebrew and local binary paths are on PATH
export PATH="$HOME/.local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.linuxbrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

OS="$(uname -s)"

echo "🚀 Setting up dotfiles..."

if [ "$OS" = "Darwin" ]; then
    if xcode-select -p > /dev/null 2>&1; then
        echo "✅ Xcode CLI tools already installed."
    else
        echo "🔧 Installing Xcode CLI tools..."
        xcode-select --install > /dev/null 2>&1 || true
        while ! xcode-select -p > /dev/null 2>&1; do sleep 5; done
        echo "✅ Xcode CLI tools installed."
    fi

    if ! command -v brew > /dev/null 2>&1; then
        echo "🔧 Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
        if [ -d "/opt/homebrew/bin" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -d "/usr/local/bin" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    if command -v brew > /dev/null 2>&1; then
        echo "🔧 Installing age and chezmoi..."
        brew install age chezmoi
    else
        echo "🔧 Installing chezmoi..."
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    fi

elif [ "$OS" = "Linux" ]; then
    echo "🔧 Installing system dependencies..."
    if command -v apt-get > /dev/null 2>&1; then
        sudo apt-get update -y
        sudo apt-get install -y curl age build-essential procps file git || true
    fi

    if ! command -v brew > /dev/null 2>&1; then
        echo "🔧 Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
        if [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        elif [ -d "$HOME/.linuxbrew/bin" ]; then
            eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
        fi
    fi

    # Install chezmoi if not already installed
    if ! command -v chezmoi > /dev/null 2>&1; then
        echo "🔧 Installing chezmoi..."
        if command -v brew > /dev/null 2>&1; then
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
