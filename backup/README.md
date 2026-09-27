# Back up, erase, and restore a personal Mac

This guide uses the scripts in [`scripts/`](scripts/) to move local data to an
external SSD, set up macOS and Chezmoi, then restore the data. Use the same macOS
user account name if you want paths in projects and app settings to stay the
same. Replace `YourSSD` in the commands with the volume name shown in Finder.

## 1. Back up before erasing

Use a mounted SSD with enough free space. An encrypted APFS volume is a good
choice for a backup containing SSH keys and browser profiles. Keep the SSD
connected until the backup and checks finish. Quit Zen, Helium, Zotero,
Raycast, Ice, Velja, Shottr, DockDoor, Boring Notch, Hyperkey, and other apps
whose data is being copied. If macOS asks Terminal for access to
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
snapshot. The script refuses a destination that is not a mounted volume under
`/Volumes`.

The script copies `~/Developer`, `~/Downloads`, `~/Documents`, `~/.ssh`, the Zen,
and Helium profile directories, plus `~/Pictures`, `~/Study`, `~/Work`,
`~/Desktop`, `~/.gemini`, and the default `~/Zotero` directory. It exports
preferences for Raycast, Ice, Velja, Shottr, DockDoor, Boring Notch, and Hyperkey,
and copies local Raycast data plus the Velja, Shottr, and Boring Notch containers.
It also copies Chrome's folder if present, though Chrome is not
used on this Mac. The script checks copied files by checksum and stops if a
required source is missing or a copy differs. Check warnings for optional data:
a custom Zotero location or a different Helium profile path needs a separate
copy. Other app data, macOS Keychain items, and Chezmoi's saved answers are not
included. App accounts and some saved credentials may need sign-in again
after the erase; confirm you can access your password manager, recovery codes,
and two-factor authentication. A separate Time Machine backup is useful if you
need to recover anything outside these folders.

### Keep open tabs

The profile copies include browser session files when the browser has saved
them, but restoring a profile does not guarantee that every window reopens.
Before quitting the browsers, save important open tabs as bookmarks or export
their URLs. Private/incognito tabs and unsaved form contents should not be
counted on. In Zen, enable its previous windows and tabs startup setting or use
**History → Restore Previous Session** after restoring. Quit each browser
normally, then run the backup.

Zen 1.22.1b and newer can also sync Spaces, folders, and tabs through a Mozilla
account: open **Settings → Sync**, sign in, and enable **Sync your Spaces across
devices**. Confirm that Mozilla Sync is enabled for your desired data types.
This gives you another route to tabs and bookmarks, but keep the full profile
backup because sync is not a complete snapshot. [Zen release notes](https://github.com/zen-browser/desktop/releases/tag/1.22.1b)
describe the new feature. [Helium has no built-in data sync yet](https://helium.computer/),
so its SSD profile copy is especially important. If you want an off-site copy,
upload an encrypted copy of the finished backup to cloud storage; do not sync
a browser's live profile directory while the browser is running.

Verify the SSD before erasing the Mac:

```bash
backup_dir="/Volumes/YourSSD/mac_backup/local_$(date +%d%m%y)"
du -sh "$backup_dir"
for item in Developer Downloads Documents ssh zen helium; do
  test -d "$backup_dir/$item" || printf 'MISSING: %s\n' "$item"
done
rsync -aicn --delete --out-format='%i %n' \
  "$HOME/Documents/" "$backup_dir/Documents/"
rsync -aicn --delete --out-format='%i %n' \
  "$HOME/Library/Application Support/zen/" "$backup_dir/zen/"
rsync -aicn --delete --out-format='%i %n' \
  "$HOME/Library/Application Support/net.imput.helium/" "$backup_dir/helium/"
```

The backup script already checks every copied directory by checksum. The three
`rsync` commands check Documents, Zen, and Helium again without changing files;
no output means each source matches the SSD copy. Check that Zen's
backup has `zen-sessions.jsonlz4` or `sessionstore-backups`, and that Helium's
backup has `Local State` and all expected `Profile *` folders with their
`Sessions` directories. Inspect any errors or differences. **Do not erase the
Mac until everything you need is present and readable on the SSD.** A checksum
match confirms copied bytes, not that a browser will reopen every tab; testing
the restore in a separate macOS account or on another Mac provides the strongest
check before erasing. Eject and disconnect the SSD after the checks.

Check `apps/preferences/` for seven plists, plus `apps/raycast/` and the app
containers you use. Missing preferences produce warnings; investigate those
before erasing. The backup preserves local settings, but macOS permissions such
as Accessibility, Screen Recording, Input Monitoring, login items, and Tailscale
VPN approval may need to be granted again. Raycast account sign-in and any
license activation may also need repeating. For another copy of Raycast's
settings, use its **Settings → Advanced → Export** to save an encrypted
`.rayconfig` file on the SSD and keep the export password. If you use Raycast
Pro, its cloud sync offers an additional recovery route. Velja can export its
rules from the **Rules** tab. Neither export replaces the full SSD backup.

If you changed the Chezmoi setup answers and want the exact same choices after
reinstalling, separately copy `~/.config/chezmoi/chezmoi.json` to the SSD, or
write down the chosen preset and overrides. If you have local dotfiles changes
that are not on GitHub, save those separately too. In particular, make sure
this guide and the backup-script changes are on GitHub or copied to the
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

The workstation GUI tier installs Tailscale through Homebrew. After signing in
to the same Apple Account, install the selected Mac App Store apps, including
Kofe Flow and Arpeggi, with `dotfiles-macos-apps`. Arpeggi requires Apple
Silicon and is omitted on Intel Macs. Sign in to Tailscale and approve its
macOS network extension when prompted.

## 3. Restore from the SSD

Reconnect the SSD and confirm its volume name. Close Zen, Helium, Zotero, and
the seven settings apps before restoring. Ideally, do this before opening those
apps and creating new profiles. Identify the exact backup folder; the restore script
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
Open each settings app and check its preferences, then regrant any macOS
permissions it requests. If Raycast's restored data is incomplete, import the
`.rayconfig` export saved earlier. Reboot or log out and back in if a restored
preference does not appear immediately.
If SSH signing was selected, run `chezmoi apply` after restoring `~/.ssh` so
Git can use the restored key. See the [main README](../README.md#commands-that-require-your-presence)
for account enrollment and Mac App Store apps. Only erase the SSD backup after
you have verified the restored data and have another backup.
