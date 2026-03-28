# rclone - Google Drive Bidirectional Sync

Local mirror of Google Drive using `rclone bisync`. Files live at `~/gdrive` as real local files and sync bidirectionally with Google Drive every 1 minute via a systemd timer, with near-instant sync on local changes via inotifywait.

## Features

- **Local files** — no FUSE mount, no network latency to open files
- **Bidirectional sync** — changes made locally or on Google Drive are synced both ways
- **Near-instant local sync** — inotifywait detects local file changes and triggers a sync within 5 seconds
- **Polling for remote changes** — 1-minute timer catches changes made on Google Drive (web, phone, etc.)
- **Offline access** — all files are always available locally
- **Local backup** — full copy of Google Drive on disk
- **Conflict resolution** — newest edit wins; the older version is kept with a `.conflict` suffix (nothing is lost)
- **Safety guardrail** — aborts if more than 50 files would be deleted in a single sync (prevents accidental mass deletion)
- **Auto-recovery** — recovers from interrupted syncs and transient network errors without manual intervention
- **Low priority** — runs at nice 10 with idle I/O scheduling so it doesn't interfere with interactive use

## Files

| File | Install location |
|---|---|
| `rclone-bisync.service` | `~/.config/systemd/user/rclone-bisync.service` |
| `rclone-bisync.timer` | `~/.config/systemd/user/rclone-bisync.timer` |
| `rclone-bisync-watch.sh` | `~/.local/bin/rclone-bisync-watch.sh` |
| `rclone-bisync-watch.service` | `~/.config/systemd/user/rclone-bisync-watch.service` |

## Setup

### Prerequisites

```bash
# Install rclone and inotify-tools
sudo dnf install rclone inotify-tools

# Configure the Google Drive remote (follow the interactive prompts)
rclone config
# Create a remote named "gdrive" with type "drive" and scope "drive"
```

### Install

```bash
# Create the log directory
mkdir -p ~/.local/share/rclone

# Copy the unit files
cp rclone-bisync.service ~/.config/systemd/user/
cp rclone-bisync.timer ~/.config/systemd/user/
cp rclone-bisync-watch.service ~/.config/systemd/user/

# Copy the watcher script
cp rclone-bisync-watch.sh ~/.local/bin/
chmod +x ~/.local/bin/rclone-bisync-watch.sh

# Initial sync (downloads everything from Google Drive — takes a while)
rclone bisync ~/gdrive gdrive: \
  --resync \
  --resync-mode path2 \
  --transfers 8 \
  --checkers 16 \
  --create-empty-src-dirs \
  --fix-case

# Enable and start the timer and watcher
systemctl --user daemon-reload
systemctl --user enable --now rclone-bisync.timer
systemctl --user enable --now rclone-bisync-watch.service
```

## Useful Commands

```bash
# Trigger an immediate sync
systemctl --user start rclone-bisync.service

# Check sync status
systemctl --user status rclone-bisync.service

# Check watcher status
systemctl --user status rclone-bisync-watch.service

# View the timer schedule
systemctl --user list-timers | grep bisync

# View sync logs
tail -50 ~/.local/share/rclone/bisync.log

# Check Google Drive storage usage
rclone about gdrive:

# Force sync when more than 50 deletions are needed (e.g. bulk cleanup)
rclone bisync ~/gdrive gdrive: --force --resync

# Full re-sync from scratch (if state gets corrupted)
rclone bisync ~/gdrive gdrive: \
  --resync \
  --resync-mode path2 \
  --transfers 8 \
  --checkers 16 \
  --create-empty-src-dirs \
  --fix-case
```

## How It Works

- **Local changes**: `rclone-bisync-watch.service` runs inotifywait, watching `~/gdrive` recursively for creates, deletes, modifications, and moves. After 5 seconds of no new events (debounce), it triggers a bisync.
- **Remote changes**: `rclone-bisync.timer` fires every 1 minute to catch changes made via Google Drive web, phone, or other devices.
- Both trigger the same `rclone-bisync.service`, which runs `rclone bisync` as a oneshot.
- rclone compares file listings from both sides against the previous sync state to detect changes.
- New/modified files are copied in the appropriate direction; deletions are propagated.
- Bisync state is stored in `~/.cache/rclone/bisync/`.
- If a file is modified on both sides between syncs, the newer version wins and the older is renamed with a `.conflict` suffix.

## Verification

After setup, run these steps to confirm everything is working:

```bash
# 1. Check the timer is active and firing every ~1 minute
systemctl --user list-timers | grep bisync

# 2. Check the file watcher is running
systemctl --user status rclone-bisync-watch.service

# 3. Test local → remote sync (inotify-triggered, should appear within ~7 seconds)
touch ~/gdrive/test-sync.txt
sleep 7
rclone lsf gdrive: | grep test-sync

# 4. Test remote → local sync
#    Delete the test file from Google Drive (web/phone) or via:
rclone delete gdrive:test-sync.txt
#    Then wait ~1 minute or trigger manually:
systemctl --user start rclone-bisync.service
ls ~/gdrive/test-sync.txt  # should say "No such file or directory"

# 5. Verify file counts match
rclone size gdrive:
find ~/gdrive -type f | wc -l

# 6. Check logs for errors
tail -20 ~/.local/share/rclone/bisync.log
```

## Notes

- Deleted files are recoverable from Google Drive's trash for 30 days
- Google Docs/Sheets/Slides are exported as .docx/.xlsx/.pptx locally
- The `--max-delete 50` limit can be overridden with `--force` for intentional bulk operations
