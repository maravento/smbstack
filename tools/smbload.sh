#!/bin/bash
# maravento.com
#
################################################################################
#
# smbload -- service watchdog for smbstack
#
# DESCRIPTION:
# Checks smbd, winbind and smbwatch, and starts whatever is down.
# Requires root.
#
# USAGE:
# sudo bash smbload.sh    Run one check now
#
# LOG: /var/log/smbload.log
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
        log "INFO: smbd restarted -- fixed"
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
        log "INFO: winbind restarted -- fixed"
    else
        log "WARNING: winbind restart FAILED -- alert"
    fi
fi

# ------------------------------------------------------------------------------
# WATCHDOG
# ------------------------------------------------------------------------------

# SMBwatch Service
script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
pid_file="/run/smbstack-smbwatch.pid"

is_smbwatch_running() {
    local watch_pid="$1" process_group
    kill -0 "$watch_pid" 2>/dev/null || return 1
    process_group=$(ps -o pgid= -p "$watch_pid" 2>/dev/null | tr -d ' ')
    [ -n "$process_group" ] && pgrep -g "$process_group" -x inotifywait >/dev/null 2>&1
}

if [ ! -x "$script_dir/smbwatch.sh" ]; then
    log "WARNING: smbwatch.sh not found or not executable -- alert"
elif [ -f "$pid_file" ] && is_smbwatch_running "$(cat "$pid_file")"; then
    log "INFO: smbwatch ONLINE"
else
    if "$script_dir/smbwatch.sh" start &>/dev/null; then
        log "INFO: smbwatch restarted -- fixed"
    else
        log "WARNING: smbwatch restart FAILED, see smbwatch.log -- alert"
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbload done at: $(date '+%Y-%m-%d %H:%M:%S')"
