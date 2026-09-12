#!/bin/bash
# maravento.com
#
################################################################################
#
# smbload - Service Watchdog
# https://github.com/maravento/smbstack
#
# Checks smbd and winbind, and starts them if they are down.
# Also checks smbwatch.sh and restarts it if it is not running, but only
# once WATCH_LIMIT_GB and WATCH_EXCLUDE exist in smbstack.env, which happens
# after smbwatch.sh has been started interactively for the first time.
#
# log: /var/log/smbload.log (rewritten on each run)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/smbload.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep_pkg in procps samba winbind util-linux coreutils sed systemd; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: dependency '$dep_pkg' is not installed -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# SERVICES
# ------------------------------------------------------------------------------

# start
log "smbload start..."

# Samba Service (smbd)
if pgrep -x smbd > /dev/null; then
    log "INFO: smbd ONLINE"
else
    systemctl stop smbd.service &>/dev/null
    if systemctl start smbd.service; then
        log "FIX: smbd restarted"
    else
        log "WARNING: smbd restart FAILED -- alert"
    fi
fi

# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    log "INFO: winbind ONLINE"
else
    systemctl stop winbind.service &>/dev/null
    if systemctl start winbind.service; then
        log "FIX: winbind restarted"
    else
        log "WARNING: winbind restart FAILED -- alert"
    fi
fi

# ------------------------------------------------------------------------------
# WATCHDOG
# ------------------------------------------------------------------------------

# SMBwatch Service (inert until smbwatch.sh has written its keys to smbstack.env)
script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
smbstack_env="/var/www/smbstack/smbstack.env"
pid_file="/run/smbstack-smbwatch.pid"

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

is_smbwatch_running() {
    local watch_pid="$1" process_group
    kill -0 "$watch_pid" 2>/dev/null || return 1
    process_group=$(ps -o pgid= -p "$watch_pid" 2>/dev/null | tr -d ' ')
    [ -n "$process_group" ] && pgrep -g "$process_group" -x inotifywait >/dev/null 2>&1
}

watch_limit_gb=""
watch_exclude=""
if [ -f "$smbstack_env" ]; then
    watch_limit_gb=$(sed -n 's/^WATCH_LIMIT_GB=//p' "$smbstack_env" | tr -d '"' | tail -n 1)
    watch_exclude=$(sed -n 's/^WATCH_EXCLUDE=//p' "$smbstack_env" | tr -d '"' | tail -n 1)
fi

if [ -z "$watch_limit_gb" ] || [ -z "$watch_exclude" ]; then
    log "WARNING: WATCH_LIMIT_GB/WATCH_EXCLUDE not set -- skip"
elif ! [[ "$watch_limit_gb" =~ $UH_UINT ]] || [ "$watch_limit_gb" -lt 1 ] || [ "$watch_limit_gb" -gt 10000 ]; then
    log "WARNING: invalid WATCH_LIMIT_GB in $(basename "$smbstack_env") -- skip"
elif [ ! -x "$script_dir/smbwatch.sh" ]; then
    log "WARNING: smbwatch.sh not found or not executable -- skip"
elif [ -f "$pid_file" ] && is_smbwatch_running "$(cat "$pid_file")"; then
    log "INFO: smbwatch ONLINE"
else
    if "$script_dir/smbwatch.sh" start &>/dev/null; then
        log "FIX: smbwatch restarted"
    else
        log "WARNING: smbwatch restart FAILED -- alert"
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbload done at: $(date)"
