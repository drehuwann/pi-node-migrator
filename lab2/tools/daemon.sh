#!/bin/bash
#
# daemon.sh - Root-side mount/umount daemon for the Windows ISO processing pipeline.
#
# This script is intentionally NOT executable by default. It must be launched
# explicitly by the main script using:
#
#     sudo RUNNER=<user> bash daemon.sh <cmd_fifo> <resp_fifo> <log_file>
#
# Rationale:
# - Prevent accidental execution by users or tools.
# - Ensure the daemon always runs under sudo/root.
# - Ensure the daemon always receives the correct FIFO paths.
# - Avoid protocol corruption caused by running the daemon outside its context.
#
# The daemon reads commands from CMD_FIFO and writes responses to RESP_FIFO.
# Protocol:
#   READY <pid>        sent once at startup
#   mount <iso> <dir>  mount ISO read-only via loop
#   umount <dir>       unmount directory
#   quit               stop daemon
#
# Responses:
#   OK
#   ERR <message>
#
# All output except protocol responses is written to LOG_FILE.
#
CMD_FIFO="$1"
RESP_FIFO="$2"
DAEMON_LOG="$3"
if [ -z "$CMD_FIFO" ] || [ -z "$RESP_FIFO" ] || [ -z "$DAEMON_LOG" ]; then
    echo "daemon.sh: missing arguments" >&2
    exit 1
fi
# Logging helper
log() {
    printf "[%s] %s\n" "$(date '+%F %T')" "$*" >> "$DAEMON_LOG"
}
# Cleanup on exit
cleanup() {
    log "Daemon exiting with code $?"
    # Do NOT write anything to RESP_FIFO here.
    # Writing to the FIFO during shutdown corrupts the protocol.
    rm -f "$RESP_FIFO" 2>/dev/null
}
trap cleanup EXIT
log "Daemon started (RUNNER=$RUNNER)"
# Send READY + PID
log "Sending READY with PID $$"
printf "READY %s\n" "$$" > "$RESP_FIFO"
# Main loop
while read -r cmd arg1 arg2; do
    log "Received command: $cmd $arg1 $arg2"
    case "$cmd" in
        mount)
            if mount -o loop,ro "$arg1" "$arg2" 2>/dev/null; then
                chown -R "$RUNNER:$RUNNER" "$arg2" 2>/dev/null
                printf "OK\n" > "$RESP_FIFO"
                log "Mount OK: $arg1 -> $arg2"
            else
                printf "ERR mount %s\n" "$arg1" > "$RESP_FIFO"
                log "Mount ERROR: $arg1"
            fi
            ;;
        umount)
            if umount "$arg1" 2>/dev/null; then
                printf "OK\n" > "$RESP_FIFO"
                log "Umount OK: $arg1"
            else
                printf "ERR umount %s\n" "$arg1" > "$RESP_FIFO"
                log "Umount ERROR: $arg1"
            fi
            ;;
        quit)
            printf "OK\n" > "$RESP_FIFO"
            log "Quit received - stopping daemon"
            break
            ;;
        *)
            printf "ERR unknown_cmd %s\n" "$cmd" > "$RESP_FIFO"
            log "Unknown command: $cmd"
            ;;
    esac
done < "$CMD_FIFO"
log "Daemon stopped"
exit 0
