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

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/smbwatch.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# dependencies
for dep_pkg in inotify-tools procps coreutils findutils cron util-linux; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: dependency '$dep_pkg' is not installed -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
script_path="$script_dir/$(basename "$0")"
smbstack_env="/var/www/smbstack/smbstack.env"
run_dir="/run"
mkdir -p "$run_dir"
pid_file="$run_dir/smbstack-smbwatch.pid"
state_file="$run_dir/smbstack-smbwatch.state"

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# $! only captures the PID of the last stage of the "inotifywait | while read"
# pipeline (the subshell), not inotifywait itself. Guard against that PID
# being alive on its own (or reused by an unrelated process) by also
# confirming a real inotifywait process exists in the same process group.
is_smbwatch_running() {
    local watch_pid="$1" process_group
    kill -0 "$watch_pid" 2>/dev/null || return 1
    process_group=$(ps -o pgid= -p "$watch_pid" 2>/dev/null | tr -d ' ')
    [ -n "$process_group" ] && pgrep -g "$process_group" -x inotifywait >/dev/null 2>&1
}

# LOAD ENV
# Abort if smbstack is not installed, then read its .env file
if [ ! -f "$smbstack_env" ]; then
    log "ERROR: smbstack is not installed -- abort"
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
    while IFS= read -r env_line; do
        if [[ "$env_line" =~ ^[A-Z_]+=.* ]]; then
            env_key="${env_line%%=*}"
            env_value="${env_line#*=}"
            env_value="${env_value//\"}"
            case "$needed_env_keys" in
                *" $env_key "*) export "$env_key=$env_value" ;;
                *)
                    case "$known_env_keys" in
                        *" $env_key "*) ;;
                        *) log "WARNING: ignoring unknown key in $smbstack_env: $env_key" ;;
                    esac
                    ;;
            esac
        fi
    done < "$smbstack_env"
}
load_env

set_env_var() {
    local env_key="$1" env_value="$2"
    local esc_val
    env_value=$(printf '%s' "$env_value" | tr -d '\r\n')
    esc_val=$(printf '%s' "$env_value" | sed -e 's/[\&|]/\\&/g')
    if grep -q "^${env_key}=" "$smbstack_env"; then
        sed -i "s|^${env_key}=.*|${env_key}=\"${esc_val}\"|" "$smbstack_env"
    else
        echo "${env_key}=\"${env_value}\"" >> "$smbstack_env"
    fi
}

# HANDLE NEW FILE
# Move a newly created file to the recycle folder when it exceeds the limit
handle_new_file() {
    local new_file="$1"
    sleep 1

    [ ! -e "$new_file" ] && return

    local rel_path="${new_file#"$SHARED_PATH"/}"
    local watched_dir="$SHARED_PATH/${rel_path%%/*}"

    local dir_size
    dir_size=$(du -sb "$watched_dir" 2>/dev/null | awk '{print $1}')
    [[ "$dir_size" =~ $UH_UINT ]] || dir_size=0

    if [ "$dir_size" -ge "$size_limit" ]; then
        mkdir -p "$recycle_dir"
        chown "${LOCAL_USER:-root}":sambashare "$recycle_dir" 2>/dev/null || true
        chmod 775 "$recycle_dir"
        local recycle_date
        recycle_date=$(date +%Y%m%d)
        local dest_path="$recycle_dir/$recycle_date"
        mkdir -p "$dest_path"
        chown "${LOCAL_USER:-root}":sambashare "$dest_path"
        chmod 775 "$dest_path"

        if [ -f "$new_file" ]; then
            mv -f "$new_file" "$dest_path/$(basename "$new_file")"
            log "Moved file to recycle: $new_file -> $dest_path"
        elif [ -d "$new_file" ] && [ -z "$(ls -A "$new_file")" ]; then
            mv -f "$new_file" "$dest_path/$(basename "$new_file")"
            log "Moved empty dir to recycle: $new_file -> $dest_path"
        fi
    fi
}

# START
# Launch the inotifywait watcher in background and write its pid file
start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
        log "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    if [ -f "$pid_file" ] && is_smbwatch_running "$(cat "$pid_file")"; then
        log "SMBwatch is already running with PID $(cat "$pid_file")"
        exit 1
    fi

    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 640 "$log_file"
        chown root:root "$log_file"
    fi

    # CHECK AND SET WATCH_LIMIT_GB
    if [ -z "${WATCH_LIMIT_GB:-}" ]; then
        while true; do
            read -p "Enter watch limit per folder in GB [10]: " input_limit
            input_limit="${input_limit:-10}"
            if [[ "$input_limit" =~ $UH_UINT ]] && [ "$input_limit" -gt 0 ] && [ "$input_limit" -le 10000 ]; then
                WATCH_LIMIT_GB="$input_limit"
                set_env_var "WATCH_LIMIT_GB" "$WATCH_LIMIT_GB"
                log "Watch limit set to ${WATCH_LIMIT_GB} GB"
                break
            else
                log "ERROR: Enter a valid number between 1 and 10000"
            fi
        done
    fi

    # CHECK AND SET WATCH_EXCLUDE
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

    size_limit=$((WATCH_LIMIT_GB * 1024 * 1024 * 1024))

    # BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding hidden dirs and excluded folders)
    if [ -z "${SHARED_PATH:-}" ] || [ ! -d "$SHARED_PATH" ]; then
        log "ERROR: SHARED_PATH is not set or does not exist. Check $smbstack_env"
        exit 1
    fi

    recycle_dir="$SHARED_PATH/.recycle/smbwatch"
    watch_dirs=()
    IFS=',' read -ra exclude_list <<< "${WATCH_EXCLUDE:-}"
    while IFS= read -r -d '' shared_subdir; do
        dir_name="$(basename "$shared_subdir")"
        [[ "$dir_name" == .* ]] && continue
        is_excluded=0
        for excluded_name in "${exclude_list[@]}"; do
            excluded_name="${excluded_name#"${excluded_name%%[![:space:]]*}"}" ; excluded_name="${excluded_name%"${excluded_name##*[![:space:]]}"}"
            [ "$dir_name" = "$excluded_name" ] && is_excluded=1 && break
        done
        [ "$is_excluded" -eq 1 ] && continue
        watch_dirs+=("$shared_subdir")
    done < <(find "$SHARED_PATH" -mindepth 1 -maxdepth 1 -type d -print0)

    if [ "${#watch_dirs[@]}" -eq 0 ]; then
        log "ERROR: No subdirectories found in $SHARED_PATH"
        exit 1
    fi

    printf '%s\n' "${watch_dirs[@]}" > "$state_file"

    log "Starting smbwatch..."
    log "  Shared path : $SHARED_PATH"
    log "  Watch limit : ${WATCH_LIMIT_GB} GB per folder"
    log "  Watching    :"
    printf '    %s\n' "${watch_dirs[@]}" | tee -a "$log_file"
    log "  Excluded    : ${WATCH_EXCLUDE:-none}"
    log "  Recycle bin : $recycle_dir"
    log "  Log         : $log_file"

    inotifywait -m -r -e create --format '%w%f' "${watch_dirs[@]}" 2>>"$log_file" | while read -r new_file; do
        handle_new_file "$new_file"
    done &

    echo $! > "$pid_file"
    log "SMBwatch started with PID $(cat "$pid_file")"

    # add @reboot cron entry if not already present
    if ! crontab -l 2>/dev/null | grep -q "smbwatch.sh start"; then
        crontab -l 2>/dev/null > "$script_dir/crontab-$(date +%Y%m%d%H%M%S).bak" || true
        (crontab -l 2>/dev/null; echo "@reboot $script_path start") | crontab -
        log "Added to cron @reboot"
    fi
}

# STOP
# Kill the watcher process group and remove its pid file
stop() {
    log "Stopping smbwatch..."
    if [ -f "$pid_file" ]; then
        local watch_pid process_group
        watch_pid=$(cat "$pid_file")
        if kill -0 "$watch_pid" 2>/dev/null; then
            process_group=$(ps -o pgid= -p "$watch_pid" 2>/dev/null | tr -d ' ')
            if [ -n "$process_group" ]; then
                kill -- "-$process_group" 2>/dev/null
            else
                kill "$watch_pid" 2>/dev/null
            fi
            log "SMBwatch stopped (PID $watch_pid)"
        else
            log "SMBwatch was not running (stale PID file removed)"
        fi
        rm -f "$pid_file" "$state_file"
    else
        log "SMBwatch is not running"
    fi
}

# STATUS
# Report whether the watcher is running
status() {
    log "SMBwatch status..."
    if [ -f "$pid_file" ] && is_smbwatch_running "$(cat "$pid_file")"; then
        log "  SMBwatch is RUNNING (PID $(cat "$pid_file"))"
        log "  Watch limit : ${WATCH_LIMIT_GB:-not set} GB per folder"
        if [ -f "$state_file" ]; then
            log "  Watching    :"
            sed 's/^/    /' "$state_file" | tee -a "$log_file"
        else
            log "  Watching    : (unknown, state file missing)"
        fi
    else
        log "  SMBwatch is STOPPED"
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      log "Usage: $(basename "$0") {start|stop|status}" ;;
esac
