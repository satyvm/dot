# Back up, erase, and restore a personal Mac

This guide uses the scripts in [`scripts/`](scripts/) to move local data to an
external SSD, set up macOS and Chezmoi, then restore the data. Use the same macOS
user account name if you want paths in projects and app settings to stay the
same. Replace `YourSSD` in the commands with the volume name shown in Finder.

## 1. Back up before erasing

Use a mounted SSD with enough free space. An encrypted APFS volume is a good
choice for a backup containing SSH keys and browser profiles. Keep the SSD
connected until the backup and checks finish. Quit Zen, Helium, Chrome, Zotero,
and other apps whose data is being copied. If macOS asks Terminal for access to
Documents, Downloads, Desktop, or browser data, allow it and rerun the backup
after any permission error.

From Terminal on the current Mac:

```bash
bash "$(chezmoi source-path)/backup/scripts/executable_backup-local.sh" "/Volumes/YourSSD"
```

Pass the SSD path explicitly. The script also accepts no argument, but then it
uses the first non-system volume under `/Volumes`. It writes to
`/Volumes/YourSSD/mac_backup/local_DDMMYY` using today's date. **Running it
again on the same day updates that folder and deletes files there that are no
longer present at the source.** Keep a separate copy if you need an earlier
snapshot.

The script copies `~/Developer`, `~/Downloads`, `~/Documents`, `~/.ssh`, the Zen,
Helium, and Chrome profile directories, plus `~/Pictures`, `~/Study`, `~/Work`,
`~/Desktop`, `~/.gemini`, and the default `~/Zotero` directory. It exports Velja
preferences. It prints a warning for any missing source. Check those warnings:
a custom Zotero location or a different Helium profile path needs a separate
copy. Other app data, macOS Keychain items, and Chezmoi's saved answers are not
included. Browser accounts and some saved credentials may need sign-in again
after the erase; confirm you can access your password manager, recovery codes,
and two-factor authentication. A separate Time Machine backup is useful if you
need to recover anything outside these folders.

Verify the SSD before erasing the Mac:

```bash
backup_dir="/Volumes/YourSSD/mac_backup/local_$(date +%d%m%y)"
du -sh "$backup_dir"
for item in Developer Downloads Documents ssh zen helium chrome; do
  test -d "$backup_dir/$item" || printf 'MISSING: %s\n' "$item"
done
rsync -aicn "$HOME/Documents/" "$backup_dir/Documents/"
```

The last command checks the Documents copy by checksum without changing files;
no file list means it matches. Repeat it for other important directories by
changing both `Documents` paths. Investigate missing directories and any rsync
errors or differences. The source might genuinely be absent, but **do not erase
the Mac until everything you need is present and readable on the SSD**. Eject
and disconnect the SSD after the checks. Keep it disconnected while erasing.

If you changed the Chezmoi setup answers and want the exact same choices after
reinstalling, separately copy `~/.config/chezmoi/chezmoi.json` to the SSD, or
write down the chosen preset and overrides. If you have local dotfiles changes
that are not on GitHub, save those separately too. In particular, make sure
this guide and the Chrome backup/restore changes are on GitHub or copied to the
SSD before erasing; a fresh Chezmoi install downloads the remote repository.

## 2. Erase the Mac and run Chezmoi

On a supported Mac, open **System Settings → General → Transfer or Reset → Erase
All Content and Settings**. This removes local accounts, apps, settings, and
data while keeping the installed macOS. Follow [Apple's erase instructions](https://support.apple.com/en-us/102664),
including its alternative Recovery steps if this option is unavailable. Confirm
the SSD is disconnected before selecting the disk to erase.

Finish macOS Setup Assistant, sign in to the same Apple Account as needed, and
connect to the internet. Open Terminal and run the repository bootstrap:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

Choose the `workstation` preset for the full personal Mac setup, or repeat your
previous choices. Wait for Chezmoi and the package installers to finish. The
bootstrap installs the repository at `~/.local/share/chezmoi`, including these
backup scripts, but does not restore personal files. Restart or open a new
Terminal session if the new shell tools are not yet on `PATH`.

## 3. Restore from the SSD

Reconnect the SSD and confirm its volume name. Close Zen, Helium, Chrome, and
Zotero before restoring. Ideally, do this before opening those apps and
creating new profiles. Identify the exact backup folder; the restore script
requires that folder, not just the SSD root:

```bash
eza -l "/Volumes/YourSSD/mac_backup"
bash "$(chezmoi source-path)/backup/scripts/executable_restore-local.sh" \
  "/Volumes/YourSSD/mac_backup/local_DDMMYY"
```

Replace `DDMMYY` with the folder you verified before erasing. Read the restore
output. For browser profiles, SSH, Gemini, and Zotero, an existing destination
is first moved aside to a `.bak_YYYYMMDD_HHMMSS` path. For `~/Developer`,
`~/Downloads`, `~/Documents`, and the other personal folders, the script
restores into an empty folder but **skips a nonempty folder**. If one is skipped,
keep its new files and copy the missing backup contents into it after reviewing
any name conflicts. For example:

```bash
rsync -aP --ignore-existing \
  "/Volumes/YourSSD/mac_backup/local_DDMMYY/Downloads/" "$HOME/Downloads/"
```

That example preserves files already in Downloads; inspect same-named files
manually because `--ignore-existing` skips them. Repeat with another folder
name if needed. Keep the SSD until every skipped folder has been reconciled.

Check a few projects and documents, test SSH access, and open each browser to
confirm profiles, bookmarks, and extensions. Sign in again where required.
If SSH signing was selected, run `chezmoi apply` after restoring `~/.ssh` so
Git can use the restored key. See the [main README](../README.md#commands-that-require-your-presence)
for account enrollment and Mac App Store apps. Only erase the SSD backup after
you have verified the restored data and have another backup.
