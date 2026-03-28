#!/bin/bash
# Watch ~/gdrive for local changes and trigger rclone bisync immediately.
# Debounces events — waits 5 seconds after the last change before syncing.

WATCH_DIR="$HOME/gdrive"
DEBOUNCE_SEC=5

inotifywait -m -r -e create -e delete -e modify -e move "$WATCH_DIR" --format '%w%f' |
while read -r file; do
    # Reset the debounce timer on each event
    if [ -n "$TIMER_PID" ] && kill -0 "$TIMER_PID" 2>/dev/null; then
        kill "$TIMER_PID" 2>/dev/null
    fi
    (
        sleep "$DEBOUNCE_SEC"
        systemctl --user start rclone-bisync.service
    ) &
    TIMER_PID=$!
done
