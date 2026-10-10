#!/bin/bash
# maravento.com
#
################################################################################
#
# smbwatch -- shared folder size monitor for smbstack
#
# DESCRIPTION:
# Watches the first-level folders of the shared folder, and recycles the
# file that pushes one over its limit. Requires root.
#
# USAGE:
# sudo bash smbwatch.sh install      Ask for the keys and start the watcher
# sudo bash smbwatch.sh uninstall    Remove the cron entry and the keys
# sudo bash smbwatch.sh start        Start the watcher
# sudo bash smbwatch.sh stop         Stop the watcher
# sudo bash smbwatch.sh status       Report whether the watcher runs
#
# LOG: /var/log/smbwatch.log
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
smbstack_env="/etc/smbstack/smbstack.env"
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

# wait for the mounted path
wait_mounted_path() {
    local target_path="$1" max_attempts="${2:-12}" attempt=1

    while (( attempt <= max_attempts )); do
        [ -d "$target_path" ] && return 0
        log "INFO: waiting for $(basename "$target_path") ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

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
        install -d -o root -g root -m 755 "$recycle_dir"
        local recycle_date
        recycle_date=$(date +%Y%m%d)
        local dest_path="$recycle_dir/$recycle_date"
        install -d -o root -g root -m 755 "$dest_path"

        if [ -f "$new_file" ]; then
            mv -f --backup=numbered "$new_file" "$dest_path/$(basename "$new_file")"
            touch "$dest_path/$(basename "$new_file")"
            log "INFO: moved to recycle: $(basename "$new_file")"
        elif [ -d "$new_file" ] && [ -z "$(ls -A "$new_file")" ]; then
            mv -f "$new_file" "$dest_path/$(basename "$new_file")"
            touch "$dest_path/$(basename "$new_file")"
            log "INFO: moved empty dir to recycle: $(basename "$new_file")"
        fi
    fi
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
env_specs=("$smbstack_env root:www-data 640")
for env_spec in "${env_specs[@]}"; do
    read -r env_path env_owner_want env_perms_want <<< "$env_spec"
    if [ ! -f "$env_path" ]; then
        log "ERROR: $(basename "$env_path") not found -- abort"
        exit 1
    fi
    env_owner=$(stat -c '%U:%G' "$env_path" 2>/dev/null)
    env_perms=$(stat -c '%a' "$env_path" 2>/dev/null)
    if [[ "$env_owner" != "$env_owner_want" ]] \
       || [[ "$env_perms" != "$env_perms_want" ]]; then
        if chown "$env_owner_want" "$env_path" 2>/dev/null \
           && chmod "$env_perms_want" "$env_path" 2>/dev/null; then
            log "INFO: $(basename "$env_path") perms fixed -- fixed"
        else
            log "ERROR: cannot fix $(basename "$env_path") perms -- abort"
            exit 1
        fi
    fi
done
unset env_specs env_spec env_path env_owner_want env_perms_want
unset env_owner env_perms

# LOAD_CONF
# Read known key=value pairs from a config file, without sourcing it
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
            log "ERROR: malformed line in $(basename "$conf_file"): '$env_line' -- abort"
            exit 1
        fi
        case "$env_key" in
            SHARED_PATH|WATCH_LIMIT_GB|WATCH_EXCLUDE)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

# LOAD
load_conf "$smbstack_env" || true

# KEY CHECK
# Deferred into a function, not run at top level: install creates the two
# WATCH keys, so a top-level check would abort before install could write
# them. stop and status do not need them either. Only start calls this.
#
# Collect every failure first, then decide -- a single abort reports them all
check_keys() {
    local key_errors key_error env_key
    key_errors=()
    for env_key in SHARED_PATH WATCH_EXCLUDE; do
        if ! grep -q "^${env_key}=" "$smbstack_env"; then
            key_errors+=("$env_key missing line")
        elif [[ -z "${!env_key:-}" ]]; then
            key_errors+=("$env_key not set")
        fi
    done
    if ! grep -q "^WATCH_LIMIT_GB=" "$smbstack_env"; then
        key_errors+=("WATCH_LIMIT_GB missing line")
    elif [[ -z "${WATCH_LIMIT_GB:-}" ]]; then
        key_errors+=("WATCH_LIMIT_GB not set")
    elif ! [[ "$WATCH_LIMIT_GB" =~ $UH_UINT ]] \
         || (( WATCH_LIMIT_GB < 1 || WATCH_LIMIT_GB > 10000 )); then
        key_errors+=("WATCH_LIMIT_GB invalid GB, expected 1 to 10000")
    fi
    if (( ${#key_errors[@]} > 0 )); then
        for key_error in "${key_errors[@]}"; do
            log "ERROR: $key_error"
        done
        log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$smbstack_env")"
        log "ERROR: run '$(basename "$0") install' first -- abort"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------------------------

# The only action that writes a key. It asks the operator, writes both WATCH
# keys into smbstack.env, registers the @reboot cron entry and then starts the
# watcher. A .env is written by an installer or by the administrator, never by
# a script in normal operation.
install_module() {
    local input_limit input_exclude watch_header_added

    if [ ! -t 0 ]; then
        log "ERROR: installation requires answering questions -- abort"
        exit 1
    fi

    # first time either key is written: wrap them in a divider block, like
    # uhm.env does for its own sections
    watch_header_added=0
    if ! grep -q '^WATCH_LIMIT_GB=' "$smbstack_env" \
       && ! grep -q '^WATCH_EXCLUDE=' "$smbstack_env"; then
        {
            echo ""
            echo "# ============================================================================="
            echo "# SMBWATCH (added by smbwatch.sh install)"
            echo "# ============================================================================="
        } >> "$smbstack_env"
        watch_header_added=1
    fi

    while true; do
        read -rp "Enter watch limit per folder in GB [10]: " input_limit
        input_limit="${input_limit:-10}"
        if [[ "$input_limit" =~ $UH_UINT ]] \
           && (( input_limit >= 1 && input_limit <= 10000 )); then
            WATCH_LIMIT_GB="$input_limit"
            set_env_var "WATCH_LIMIT_GB" "$WATCH_LIMIT_GB"
            log "INFO: watch limit set to ${WATCH_LIMIT_GB} GB"
            break
        fi
        log "INFO: enter a valid number between 1 and 10000 -- retry"
    done

    read -rp "Enter folders to exclude from watch limit (comma-separated, or leave empty): " input_exclude
    if [ -n "$input_exclude" ]; then
        WATCH_EXCLUDE="$input_exclude"
        set_env_var "WATCH_EXCLUDE" "$WATCH_EXCLUDE"
        log "INFO: excluded folders: ${WATCH_EXCLUDE}"
    else
        WATCH_EXCLUDE="NONE"
        set_env_var "WATCH_EXCLUDE" "NONE"
        log "INFO: no folders excluded"
    fi

    if [ "$watch_header_added" -eq 1 ]; then
        echo "# =============================================================================" >> "$smbstack_env"
    fi

    cron_d_set "$script_path" "@reboot root $script_path start"
    log "INFO: added to cron @reboot"

    start
}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

# Stops the watcher, drops the cron entry and removes both WATCH keys, so a
# later install starts from a clean state.
uninstall_module() {
    stop

    cron_d_set "$script_path" ""
    log "INFO: removed from cron @reboot"

    sed -i '/^WATCH_LIMIT_GB=/d; /^WATCH_EXCLUDE=/d' "$smbstack_env"
    sed -i '/^# SMBWATCH (added by smbwatch.sh/,+1d' "$smbstack_env"
    log "INFO: WATCH keys removed from $(basename "$smbstack_env")"
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

    check_keys
    [ "$WATCH_EXCLUDE" = "NONE" ] && WATCH_EXCLUDE=""

    size_limit=$((WATCH_LIMIT_GB * 1024 * 1024 * 1024))

    # BUILD WATCH_DIR from SHARED_PATH first-level subdirs (excluding hidden dirs and excluded folders)
    if ! wait_mounted_path "$SHARED_PATH"; then
        log "ERROR: shared folder $(basename "$SHARED_PATH") not available"
        log "ERROR: check the mount and start smbwatch again -- abort"
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

    # A file is handled on close_write or moved_to, never on create: create
    # fires the moment the transfer starts, so acting on it would measure the
    # folder and move the file while it is still being written. A file that
    # arrives by rename fires only moved_to, so a file moved in from another
    # folder would otherwise skip the limit. A directory only ever fires
    # create, and is recognized by the ISDIR flag.
    set -m
    inotifywait -m -r -e create -e close_write -e moved_to --format '%e|%w%f' "${watch_dirs[@]}" 2>>"$log_file" | while IFS='|' read -r event_name new_file; do
        case "$event_name" in
            *ISDIR*)      [[ "$event_name" == CREATE* ]] || continue ;;
            CLOSE_WRITE*|MOVED_TO*) ;;
            *)            continue ;;
        esac
        handle_new_file "$new_file"
    done &

    echo $! > "$pid_file"
    set +m
    log "INFO: started with PID $(cat "$pid_file")"

}

# STOP
# Kill the watcher process group and remove its pid file
stop() {
    log "INFO: Stopping smbwatch..."
    if [ -f "$pid_file" ]; then
        local watch_pid process_group
        watch_pid=$(cat "$pid_file")
        if is_smbwatch_running "$watch_pid"; then
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
    install)   install_module ;;
    uninstall) uninstall_module ;;
    start)     start ;;
    stop)      stop ;;
    status)    status ;;
    *)         log "INFO: Usage: $(basename "$0") {install|uninstall|start|stop|status}" ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbwatch done at: $(date '+%Y-%m-%d %H:%M:%S')"
