#!/bin/bash
# maravento.com
#
################################################################################
#
# smbbk - configuration backup for smbstack
#
# DESCRIPTION:
# Creates one compressed archive containing the project installation and
# relevant system configuration. Paths that do not exist are skipped with
# a notice.
#
# Run it by hand before applying changes, or let the monthly cron entry
# do it. Restore by unzipping the archive over /.
#
# USAGE:
# sudo bash smbbk.sh            Create a backup now
# sudo bash smbbk.sh install    Register the @monthly cron entry
# sudo bash smbbk.sh uninstall  Remove the cron entry (keeps archives)
#
# OUTPUT:
# /etc/bak/smbstack/smbbk_<YYYYMMDD_HHMM>.zip
#
# LOG: 
# /var/log/smbstack.log
#
################################################################################

set -euo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/smbstack.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort" >&2
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
for dep_pkg in zip coreutils util-linux cron; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: missing dependency '$dep_pkg' -- abort"
        exit 1
    fi
done

# local_user detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    log "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi

echo "Using local user: $local_user"

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

backup_dir="/etc/bak/smbstack"
backup_zip="${backup_dir}/smbbk_$(date +%Y%m%d_%H%M).zip"
installed_path="/etc/smbstack/tools/$(basename "$0")"
smbstack_env="/var/www/smbstack/smbstack.env"

# temp file for user/group snapshot -- always cleaned up on exit
tmp_users_file=$(mktemp)
chmod 600 "$tmp_users_file"
trap 'rm -f "$tmp_users_file"' EXIT

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

# Monthly is the floor, not a recommendation: it exists so an untouched
# system still has a recent copy. Run it by hand before any change.
register_cron() {
    # Deploy self first: the cron entry must point at a path that exists,
    # whether this ran from the repo or from its final location.
    local script_path
    script_path="$(readlink -f "$0")"
    if [ "$script_path" != "$installed_path" ]; then
        if ! mkdir -p "$(dirname "$installed_path")"; then
            log "ERROR: cannot create $(dirname "$installed_path") -- abort"
            exit 1
        fi
        install -m 755 -o root -g root "$script_path" "$installed_path"
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path"
    log "INFO: cron entry registered, runs @monthly"
    log "INFO: $installed_path"

    # legacy entry in root's crontab, from versions before /etc/cron.d
    crontab -l 2>/dev/null | { grep -vF "$installed_path" || true; } | crontab - 2>/dev/null || true
}

deregister_cron() {
    cron_d_set "$installed_path" ""
    log "INFO: cron entry removed, archives kept"

    # legacy entry in root's crontab, from versions before /etc/cron.d
    crontab -l 2>/dev/null | { grep -vF "$installed_path" || true; } | crontab - 2>/dev/null || true
}

case "${1:-}" in
    install)
        register_cron
        exit 0
        ;;
    uninstall)
        deregister_cron
        exit 0
        ;;
    "")
        ;;
    *)
        log "ERROR: unknown action '$1' -- abort"
        log "ERROR: use no argument, 'install' or 'uninstall'"
        exit 1
        ;;
esac

# Start
log "smbbk start..."

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

if ! mkdir -p "$backup_dir"; then
    log "ERROR: cannot create $backup_dir -- abort"
    exit 1
fi

# load LOCAL_USER from smbstack.env, if present (overrides detected local_user)
LOCAL_USER="$local_user"
if [ -f "$smbstack_env" ]; then
    env_user=$(grep -E '^LOCAL_USER=' "$smbstack_env" | cut -d= -f2 || true)
    [ -n "$env_user" ] && LOCAL_USER="$env_user"
fi

# user/group snapshot -- essential config, not covered by any file backup.
# getent failures are tolerated so a missing user/group doesn't abort the
# whole backup under set -e.
for user_entry in smbguest "${LOCAL_USER:-}"; do
    [ -n "$user_entry" ] || continue
    getent passwd "$user_entry" || true
done > "$tmp_users_file"

for group_entry in sambashare adm; do
    getent group "$group_entry" || true
done >> "$tmp_users_file"

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored.
backup_list=()
for backup_item in \
    /var/www/smbstack \
    /etc/samba/smb.conf \
    /etc/samba/acl \
    /var/lib/samba/private \
    /etc/apache2/sites-available/smbweb.conf \
    /etc/apache2/ports.conf \
    /etc/rsyslog.d/fullaudit.conf \
    /etc/rsyslog.conf \
    /etc/logrotate.d/samba \
    /etc/logrotate.d/smbwatch \
    /etc/logrotate.d/rsyslog \
    /lib/systemd/system/smbd.service \
    /etc/cron.d/smbstack \
    "$tmp_users_file"
do
    if [ -e "$backup_item" ]; then
        backup_list+=("$backup_item")
    else
        log "INFO: $backup_item not present -- skip"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: none of the expected paths exist"
    log "ERROR: is smbstack installed? -- abort"
    exit 1
fi

if zip -r -q "$backup_zip" "${backup_list[@]}"; then
    chmod 600 "$backup_zip"
    log "INFO: backup written to $backup_zip"

    # keep only the last 3
    old_backups=("$backup_dir"/smbbk_*.zip)
    if (( ${#old_backups[@]} > 3 )); then
        printf '%s\n' "${old_backups[@]}" | sort | head -n -3 | xargs -r rm -f
    fi
else
    rm -f "$backup_zip"
    log "ERROR: cannot write the archive"
    log "ERROR: $backup_zip"
    log "ERROR: check free space and permissions -- abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbbk done at: $(date '+%Y-%m-%d %H:%M:%S')"
