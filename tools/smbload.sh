#!/bin/bash
# maravento.com
#
################################################################################
#
# smbload - Service Watchdog
# https://github.com/maravento/smbstack
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
for dep_pkg in procps samba winbind util-linux; do
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
    log "smbd: ONLINE"
else
    systemctl stop smbd.service &>/dev/null
    if systemctl start smbd.service; then
        log "smbd start"
    else
        log "smbd start FAILED"
    fi
fi

# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    log "winbind: ONLINE"
else
    systemctl stop winbind.service &>/dev/null
    if systemctl start winbind.service; then
        log "winbind start"
    else
        log "winbind start FAILED"
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
log "smbload done at: $(date)"
