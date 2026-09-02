#!/bin/bash
# maravento.com
#
################################################################################
#
# smbwatch - Shared Folder Watchdog
# https://github.com/maravento/smbstack
#
# Monitors first-level subdirectories of the shared folder.
# When a subdirectory exceeds WATCH_LIMIT_GB, the triggering file
# is moved to .recycle/smbwatch/<YYYYMMDD>/ (this script's own channel,
# separate from .recycle/smbguest/ used by SMB and .recycle/www-data/
# used by the web interface).
# Folders listed in WATCH_EXCLUDE are not monitored (no size limit).
#
# The folder list is built once at startup. First-level folders can only be
# created by the administrator from the server shell (SMB clients and the web
# panel are blocked at the share root), so after adding one, restart smbwatch
# to include it.
#
# smbstack.env variables:
#  WATCH_LIMIT_GB  : size limit per monitored folder in GB (default: 10)
#  WATCH_EXCLUDE   : comma-separated folder names to exclude from monitoring
#                    e.g. WATCH_EXCLUDE="FINANCE,LEGAL"
#
# Log file:
#  /var/log/smbwatch.log (root:root, 640)
#  Rotated weekly via /etc/logrotate.d/smbwatch
#
# Usage:
#  ./smbwatch.sh {start|stop|status}
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/smbwatch.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

### PATHS
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
SMBSTACK_ENV="/var/www/smbstack/smbstack.env"
RUN_DIR="/run"
mkdir -p "$RUN_DIR"
PIDFILE="$RUN_DIR/smbstack-smbwatch.pid"
STATEFILE="$RUN_DIR/smbstack-smbwatch.state"

# VALIDATION -- integer only; use directly with =~
_UH_UINT='^(0|[1-9][0-9]*)$'

# $! only captures the PID of the last stage of the "inotifywait | while read"
# pipeline (the subshell), not inotifywait itself. Guard against that PID
# being alive on its own (or reused by an unrelated process) by also
# confirming a real inotifywait process exists in the same process group.
is_smbwatch_running() {
    local pid="$1" pgid
    kill -0 "$pid" 2>/dev/null || return 1
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pgid" ] && pgrep -g "$pgid" -x inotifywait >/dev/null 2>&1
}

### DEPENDENCIES
for dep in inotify-tools procps coreutils findutils cron util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done

### LOAD ENV
if [ ! -f "$SMBSTACK_ENV" ]; then
    log "ERROR: smbstack is not installed. Run smbinstall.sh --install first."
    exit 1
fi

load_env() {
    # known_env_keys: all keys smbstack.env can legitimately contain (shared
    # with smbinstall.sh/the web panel) -- not all of them are needed here,
    # but they're not suspicious either, so they're skipped silently.
    # needed_env_keys: the subset this script actually uses -- exported.
    # Anything outside known_env_keys is genuinely unexpected and gets a WARNING.
    local known_env_keys=" LOCAL_USER SHARED_NAME SHARED_PATH SMB_NET SMB_IFACE SERVER_IP SMBNAME TRUSTED_PROXIES WATCH_LIMIT_GB WATCH_EXCLUDE MAX_LOG_LINES "
    local needed_env_keys=" SHARED_PATH LOCAL_USER WATCH_LIMIT_GB WATCH_EXCLUDE "
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
            key="${line%%=*}"
            val="${line#*=}"
            val="${val//\"}"
            case "$needed_env_keys" in
                *" $key "*) export "$key=$val" ;;
                *)
                    case "$known_env_keys" in
                        *" $key "*) ;;
                        *) log "WARNING: ignoring unknown key in $SMBSTACK_ENV: $key" ;;
                    esac
                    ;;
            esac
        fi
    done < "$SMBSTACK_ENV"
}
load_env

set_env_var() {
    local key="$1" val="$2"
    local esc_val
    val=$(printf '%s' "$val" | tr -d '\r\n')
    esc_val=$(printf '%s' "$val" | sed -e 's/[\&|]/\\&/g')
    if grep -q "^${key}=" "$SMBSTACK_ENV"; then
        sed -i "s|^${key}=.*|${key}=\"${esc_val}\"|" "$SMBSTACK_ENV"
    else
        echo "${key}=\"${val}\"" >> "$SMBSTACK_ENV"
    fi
}

### HANDLE NEW FILE
handle_new_file() {
    local NEWFILE="$1"
    sleep 1

    [ ! -e "$NEWFILE" ] && return

    local REL="${NEWFILE#"$SHARED_PATH"/}"
    local TOP_DIR="$SHARED_PATH/${REL%%/*}"

    local SIZE
    SIZE=$(du -sb "$TOP_DIR" 2>/dev/null | awk '{print $1}')
    [[ "$SIZE" =~ $_UH_UINT ]] || SIZE=0

    if [ "$SIZE" -ge "$LIMIT" ]; then
        mkdir -p "$RECYCLE_DIR"
        chown "${LOCAL_USER:-root}":sambashare "$RECYCLE_DIR" 2>/dev/null || true
        chmod 775 "$RECYCLE_DIR"
        local TS
        TS=$(date +%Y%m%d)
        local DEST="$RECYCLE_DIR/$TS"
        mkdir -p "$DEST"
        chown "${LOCAL_USER:-root}":sambashare "$DEST"
        chmod 775 "$DEST"

        if [ -f "$NEWFILE" ]; then
            mv -f "$NEWFILE" "$DEST/$(basename "$NEWFILE")"
            log "Moved file to recycle: $NEWFILE -> $DEST"
        elif [ -d "$NEWFILE" ] && [ -z "$(ls -A "$NEWFILE")" ]; then
            mv -f "$NEWFILE" "$DEST/$(basename "$NEWFILE")"
            log "Moved empty dir to recycle: $NEWFILE -> $DEST"
        fi
    fi
}

### START
start() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        log "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    if [ -f "$PIDFILE" ] && is_smbwatch_running "$(cat "$PIDFILE")"; then
        log "SMBwatch is already running with PID $(cat "$PIDFILE")"
        exit 1
    fi

    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 640 "$log_file"
        chown root:root "$log_file"
    fi

    ### CHECK AND SET WATCH_LIMIT_GB
    if [ -z "${WATCH_LIMIT_GB:-}" ]; then
        while true; do
            read -p "Enter watch limit per folder in GB [10]: " input_limit
            input_limit="${input_limit:-10}"
            if [[ "$input_limit" =~ $_UH_UINT ]] && [ "$input_limit" -gt 0 ] && [ "$input_limit" -le 10000 ]; then
                WATCH_LIMIT_GB="$input_limit"
                set_env_var "WATCH_LIMIT_GB" "$WATCH_LIMIT_GB"
                log "Watch limit set to ${WATCH_LIMIT_GB} GB"
                break
            else
                log "ERROR: Enter a valid number between 1 and 10000"
            fi
        done
    fi

    ### CHECK AND SET WATCH_EXCLUDE
    if [ -z "${WATCH_EXCLUDE:-}" ]; then
        read -p "Enter folders to exclude from watch limit (comma-separated, or leave empty): " input_exclude
        if [ -n "$input_exclude" ]; then
            WATCH_EXCLUDE="$input_exclude"
            set_env_var "WATCH_EXCLUDE" "$WATCH_EXCLUDE"
            log "Excluded folders: ${WATCH_EXCLUDE}"
        else
            WATCH_EXCLUDE="NONE"
            set_env_var "WATCH_EXCLUDE" "NONE"
            log "No folders excluded"
        fi
    fi
    [ "$WATCH_EXCLUDE" = "NONE" ] && WATCH_EXCLUDE=""

    LIMIT=$((WATCH_LIMIT_GB * 1024 * 1024 * 1024))

    ### BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding hidden dirs and excluded folders)
    if [ -z "${SHARED_PATH:-}" ] || [ ! -d "$SHARED_PATH" ]; then
        log "ERROR: SHARED_PATH is not set or does not exist. Check $SMBSTACK_ENV"
        exit 1
    fi

    RECYCLE_DIR="$SHARED_PATH/.recycle/smbwatch"
    WATCH_DIRS=()
    IFS=',' read -ra EXCLUDE_LIST <<< "${WATCH_EXCLUDE:-}"
    while IFS= read -r -d '' dir; do
        dirname="$(basename "$dir")"
        [[ "$dirname" == .* ]] && continue
        excluded=0
        for ex in "${EXCLUDE_LIST[@]}"; do
            ex="${ex#"${ex%%[![:space:]]*}"}" ; ex="${ex%"${ex##*[![:space:]]}"}"
            [ "$dirname" = "$ex" ] && excluded=1 && break
        done
        [ "$excluded" -eq 1 ] && continue
        WATCH_DIRS+=("$dir")
    done < <(find "$SHARED_PATH" -mindepth 1 -maxdepth 1 -type d -print0)

    if [ "${#WATCH_DIRS[@]}" -eq 0 ]; then
        log "ERROR: No subdirectories found in $SHARED_PATH"
        exit 1
    fi

    printf '%s\n' "${WATCH_DIRS[@]}" > "$STATEFILE"

    log "Starting smbwatch..."
    log "  Shared path : $SHARED_PATH"
    log "  Watch limit : ${WATCH_LIMIT_GB} GB per folder"
    log "  Watching    :"
    printf '    %s\n' "${WATCH_DIRS[@]}" | tee -a "$log_file"
    log "  Excluded    : ${WATCH_EXCLUDE:-none}"
    log "  Recycle bin : $RECYCLE_DIR"
    log "  Log         : $log_file"

    inotifywait -m -r -e create --format '%w%f' "${WATCH_DIRS[@]}" 2>>"$log_file" | while read -r NEWFILE; do
        handle_new_file "$NEWFILE"
    done &

    echo $! > "$PIDFILE"
    log "SMBwatch started with PID $(cat "$PIDFILE")"

    # add @reboot cron entry if not already present
    if ! crontab -l 2>/dev/null | grep -q "smbwatch.sh start"; then
        crontab -l 2>/dev/null > "$SCRIPT_DIR/crontab-$(date +%Y%m%d%H%M%S).bak" || true
        (crontab -l 2>/dev/null; echo "@reboot $SCRIPT_PATH start") | crontab -
        log "Added to cron @reboot"
    fi
}

### STOP
stop() {
    log "Stopping smbwatch..."
    if [ -f "$PIDFILE" ]; then
        local PID PGID
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
            if [ -n "$PGID" ]; then
                kill -- "-$PGID" 2>/dev/null
            else
                kill "$PID" 2>/dev/null
            fi
            log "SMBwatch stopped (PID $PID)"
        else
            log "SMBwatch was not running (stale PID file removed)"
        fi
        rm -f "$PIDFILE" "$STATEFILE"
    else
        log "SMBwatch is not running"
    fi
}

### STATUS
status() {
    log "SMBwatch status..."
    if [ -f "$PIDFILE" ] && is_smbwatch_running "$(cat "$PIDFILE")"; then
        log "  SMBwatch is RUNNING (PID $(cat "$PIDFILE"))"
        log "  Watch limit : ${WATCH_LIMIT_GB} GB per folder"
        if [ -f "$STATEFILE" ]; then
            log "  Watching    :"
            sed 's/^/    /' "$STATEFILE" | tee -a "$log_file"
        else
            log "  Watching    : (unknown, state file missing)"
        fi
    else
        log "  SMBwatch is STOPPED"
    fi
}

### MAIN
case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      log "Usage: $(basename "$0") {start|stop|status}" ;;
esac
