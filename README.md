# 🌌 satyvm / dot

## Installation

To set up a fresh machine, open your terminal and run the following command.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

### Fresh Machine Setup

Before running the bootstrap script on a new machine, ensure your existing `age` private key is backed up in your **1Password** vault:

1. Open your 1Password App.
2. Create a new **Secure Note** named exactly **`chezmoi-key`**.
3. Copy the **entire** text of your age private key (from `~/.config/chezmoi/key.txt` on your active machine).
4. Paste it directly into the main **Notes** field of the `chezmoi-key` secure note.

When the bootstrap script runs, it will sign into your 1Password CLI and **automatically download and restore** your private key securely. No manual file transfers required!