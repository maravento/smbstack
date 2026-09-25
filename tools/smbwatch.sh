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
for dep_pkg in inotify-tools procps coreutils findutils cron util-linux sed grep; do
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

# CRON_D
# Add or replace one line in the project's single cron.d file
cron_d_set() {
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/smbstack"
    local cron_tmp

    cron_tmp=$(mktemp)
    [ -f "$cron_file" ] && { grep -vF "$match" "$cron_file" > "$cron_tmp" || true; }
    [ -n "$line" ] && printf '%s\n' "$line" >> "$cron_tmp"
    if [ -s "$cron_tmp" ]; then
        install -m 644 -o root -g root "$cron_tmp" "$cron_file"
    else
        rm -f "$cron_file"
    fi
    rm -f "$cron_tmp"
}

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

load_conf() {
    local conf_file="$1" env_key env_value env_line
    [[ ! -f "$conf_file" ]] && { log "WARNING: $conf_file not found -- fallback"; return 1; }
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            log "ERROR: malformed line in $conf_file: '$env_line' -- abort"
            exit 1
        fi
        case "$env_key" in
            SHARED_PATH|LOCAL_USER|WATCH_LIMIT_GB|WATCH_EXCLUDE)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}
load_conf "$smbstack_env"

set_env_var() {
    local env_key="$1" env_value="$2"
    local esc_val
    env_value=$(printf '%s' "$env_value" | tr -d '\r\n')
    esc_val=$(printf '%s' "$env_value" | sed -e 's/[\&|]/\\&/g')
    if grep -q "^${env_key}=" "$smbstack_env"; then
        sed -i "s|^${env_key}=.*|${env_key}=${esc_val}|" "$smbstack_env"
    else
        echo "${env_key}=${env_value}" >> "$smbstack_env"
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
            touch "$dest_path/$(basename "$new_file")"
            log "INFO: moved to recycle: $(basename "$new_file")"
        elif [ -d "$new_file" ] && [ -z "$(ls -A "$new_file")" ]; then
            mv -f "$new_file" "$dest_path/$(basename "$new_file")"
            touch "$dest_path/$(basename "$new_file")"
            log "INFO: moved empty dir to recycle: $(basename "$new_file")"
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
        log "ERROR: already running with PID $(cat "$pid_file") -- abort"
        exit 1
    fi

    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 640 "$log_file"
        chown root:root "$log_file"
    fi

    # keys can only be asked for interactively; under cron there is nobody to answer
    if { [ -z "${WATCH_LIMIT_GB:-}" ] || [ -z "${WATCH_EXCLUDE:-}" ]; } && [ ! -t 0 ]; then
        log "ERROR: WATCH_LIMIT_GB/WATCH_EXCLUDE not set in .env -- abort"
        exit 1
    fi

    # first time either key is written: wrap them in a divider block, like uhm.env does for its own sections
    watch_header_added=0
    if ! grep -q '^WATCH_LIMIT_GB=' "$smbstack_env" && ! grep -q '^WATCH_EXCLUDE=' "$smbstack_env"; then
        {
            echo ""
            echo "# ============================================================================="
            echo "# SMBWATCH (added by smbwatch.sh on first run)"
            echo "# ============================================================================="
        } >> "$smbstack_env"
        watch_header_added=1
    fi

    # CHECK AND SET WATCH_LIMIT_GB
    if [ -z "${WATCH_LIMIT_GB:-}" ]; then
        while true; do
            read -p "Enter watch limit per folder in GB [10]: " input_limit
            input_limit="${input_limit:-10}"
            if [[ "$input_limit" =~ $UH_UINT ]] && [ "$input_limit" -gt 0 ] && [ "$input_limit" -le 10000 ]; then
                WATCH_LIMIT_GB="$input_limit"
                set_env_var "WATCH_LIMIT_GB" "$WATCH_LIMIT_GB"
                log "INFO: watch limit set to ${WATCH_LIMIT_GB} GB"
                break
            else
                log "INFO: Enter a valid number between 1 and 10000"
            fi
        done
    fi

    # CHECK AND SET WATCH_EXCLUDE
    if [ -z "${WATCH_EXCLUDE:-}" ]; then
        read -p "Enter folders to exclude from watch limit (comma-separated, or leave empty): " input_exclude
        if [ -n "$input_exclude" ]; then
            WATCH_EXCLUDE="$input_exclude"
            set_env_var "WATCH_EXCLUDE" "$WATCH_EXCLUDE"
            log "INFO: excluded folders: ${WATCH_EXCLUDE}"
        else
            WATCH_EXCLUDE="NONE"
            set_env_var "WATCH_EXCLUDE" "NONE"
            log "INFO: no folders excluded"
        fi
    fi
    if [ "$watch_header_added" -eq 1 ]; then
        echo "# =============================================================================" >> "$smbstack_env"
    fi
    [ "$WATCH_EXCLUDE" = "NONE" ] && WATCH_EXCLUDE=""

    size_limit=$((WATCH_LIMIT_GB * 1024 * 1024 * 1024))

    # BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding hidden dirs and excluded folders)
    if [ -z "${SHARED_PATH:-}" ] || [ ! -d "$SHARED_PATH" ]; then
        log "ERROR: SHARED_PATH not set or does not exist -- abort"
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
        log "ERROR: no subdirectories found in $(basename "$SHARED_PATH") -- abort"
        exit 1
    fi

    printf '%s\n' "${watch_dirs[@]}" > "$state_file"

    log "INFO: Starting smbwatch..."
    log "INFO:   Shared path : $SHARED_PATH"
    log "INFO:   Watch limit : ${WATCH_LIMIT_GB} GB per folder"
    log "INFO:   Watching    :"
    printf '    %s\n' "${watch_dirs[@]}" | tee -a "$log_file"
    log "INFO:   Excluded    : ${WATCH_EXCLUDE:-none}"
    log "INFO:   Recycle bin : .recycle/smbwatch (under shared path)"
    log "INFO:   Log         : $log_file"

    # A file is handled on close_write, never on create: create fires the
    # moment the transfer starts, so acting on it would measure the folder
    # and move the file while it is still being written. A directory only
    # ever fires create, and is recognized by the ISDIR flag.
    inotifywait -m -r -e create -e close_write --format '%e|%w%f' "${watch_dirs[@]}" 2>>"$log_file" | while IFS='|' read -r event_name new_file; do
        case "$event_name" in
            *ISDIR*)      [[ "$event_name" == CREATE* ]] || continue ;;
            CLOSE_WRITE*) ;;
            *)            continue ;;
        esac
        handle_new_file "$new_file"
    done &

    echo $! > "$pid_file"
    log "INFO: started with PID $(cat "$pid_file")"

    # add @reboot cron entry
    cron_d_set "$script_path" "@reboot root $script_path start"
    log "INFO: added to cron @reboot"

    # legacy entry in root's crontab, from versions before /etc/cron.d
    crontab -l 2>/dev/null | { grep -vF "$script_path" || true; } | crontab - 2>/dev/null || true
}

# STOP
# Kill the watcher process group and remove its pid file
stop() {
    log "INFO: Stopping smbwatch..."
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
            log "INFO: stopped (PID $watch_pid)"
        else
            log "WARNING: stale PID file removed -- alert"
        fi
        rm -f "$pid_file" "$state_file"
    else
        log "INFO: SMBwatch is not running"
    fi
}

# STATUS
# Report whether the watcher is running
status() {
    log "INFO: SMBwatch status..."
    if [ -f "$pid_file" ] && is_smbwatch_running "$(cat "$pid_file")"; then
        log "INFO:   SMBwatch is RUNNING (PID $(cat "$pid_file"))"
        log "INFO:   Watch limit : ${WATCH_LIMIT_GB:-not set} GB per folder"
        if [ -f "$state_file" ]; then
            log "INFO:   Watching    :"
            sed 's/^/    /' "$state_file" | tee -a "$log_file"
        else
            log "INFO:   Watching    : (unknown, state file missing)"
        fi
    else
        log "INFO:   SMBwatch is STOPPED"
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "smbwatch start..."

case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      log "INFO: Usage: $(basename "$0") {start|stop|status}" ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbwatch done at: $(date '+%Y-%m-%d %H:%M:%S')"
