#!/bin/bash
# maravento.com
#
################################################################################
#
# smbreport - disk usage report for the shared folder
#
# DESCRIPTION:
# Walks the shared folder once a day and writes a JSON report with three
# tables: extensions, folders and largest files. The web panel reads that
# file and paints the Report tab; it never walks the disk itself.
#
# The walk runs as root from cron, at 03:00, when no one is working. A web
# request cannot do it: the scan takes minutes and PHP would cut it short.
#
# USAGE:
# sudo bash smbreport.sh            Build the report now
# sudo bash smbreport.sh install    Register the daily cron entry
# sudo bash smbreport.sh uninstall  Remove the cron entry (keeps the report)
#
# OUTPUT:
# /var/www/smbstack/web/smbreport.json
#
# LOG:
# /var/log/smbstack.log
#
################################################################################

set -uo pipefail

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
for dep_pkg in findutils coreutils util-linux cron; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: missing dependency '$dep_pkg' -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

smbstack_env="/var/www/smbstack/smbstack.env"
installed_path="/etc/smbstack/tools/$(basename "$0")"
report_json="/var/www/smbstack/web/smbreport.json"
top_rows=30
top_files=50

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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
            log "ERROR: malformed line in $conf_file: '$env_line' -- abort"
            exit 1
        fi
        case "$env_key" in
            SHARED_PATH)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

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

# Daily at 03:00: a full walk competes for disk with the SMB clients, so it
# runs when nobody works. The panel only reads what this leaves behind.
register_cron() {
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

    cron_d_set "$installed_path" "0 3 * * * root $installed_path"
    log "INFO: cron entry registered, runs daily at 03:00"
    log "INFO: $installed_path"

    # legacy entry in root's crontab, from versions before /etc/cron.d
    crontab -l 2>/dev/null | { grep -vF "$installed_path" || true; } | crontab - 2>/dev/null || true
}

deregister_cron() {
    cron_d_set "$installed_path" ""
    log "INFO: cron entry removed, report kept"

    # legacy entry in root's crontab, from versions before /etc/cron.d
    crontab -l 2>/dev/null | { grep -vF "$installed_path" || true; } | crontab - 2>/dev/null || true
}

# Build the JSON report from a single walk of the shared folder
build_report() {
    local scan_list total_files total_bytes report_tmp
    scan_list=$(mktemp)
    report_tmp=$(mktemp)
    trap 'rm -f "$scan_list" "$report_tmp"' RETURN

    find "$SHARED_PATH" -type f -printf '%s\t%p\n' 2>/dev/null > "$scan_list"
    total_files=$(wc -l < "$scan_list")
    total_bytes=$(awk -F'\t' '{s+=$1} END{printf "%.0f", s+0}' "$scan_list")

    {
        printf '{\n'
        printf '  "generated": "%s",\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '  "folder": "%s",\n' "$(json_escape "$SHARED_PATH")"
        printf '  "total_files": %s,\n' "$total_files"
        printf '  "total_bytes": %s,\n' "$total_bytes"

        printf '  "extensions": [\n'
        awk -F'\t' '
            { name = $2; sub(/.*\//, "", name)
              if (name ~ /.\./) { ext = tolower(name); sub(/.*\./, "", ext) } else ext = "(none)"
              count[ext]++; bytes[ext] += $1 }
            END { for (e in count) printf "%d\t%s\t%d\n", bytes[e], e, count[e] }' "$scan_list" |
            sort -t "$(printf '\t')" -k1,1nr | head -"$top_rows" |
            awk -F'\t' 'BEGIN{ORS=""}
                { gsub(/\\/, "\\\\", $2); gsub(/"/, "\\\"", $2)
                  if (NR > 1) print ",\n"
                  printf "    {\"name\": \"%s\", \"files\": %d, \"bytes\": %d}", $2, $3, $1 }
                END { print "\n" }'
        printf '  ],\n'

        printf '  "folders": [\n'
        awk -F'\t' '{ dir = $2; sub(/\/[^\/]*$/, "", dir); bytes[dir] += $1; count[dir]++ }
            END { for (d in bytes) printf "%d\t%s\t%d\n", bytes[d], d, count[d] }' "$scan_list" |
            sort -t "$(printf '\t')" -k1,1nr | head -"$top_rows" |
            awk -F'\t' 'BEGIN{ORS=""}
                { gsub(/\\/, "\\\\", $2); gsub(/"/, "\\\"", $2)
                  if (NR > 1) print ",\n"
                  printf "    {\"path\": \"%s\", \"files\": %d, \"bytes\": %d}", $2, $3, $1 }
                END { print "\n" }'
        printf '  ],\n'

        printf '  "files": [\n'
        sort -t "$(printf '\t')" -k1,1nr "$scan_list" | head -"$top_files" |
            awk -F'\t' 'BEGIN{ORS=""}
                { gsub(/\\/, "\\\\", $2); gsub(/"/, "\\\"", $2)
                  if (NR > 1) print ",\n"
                  printf "    {\"path\": \"%s\", \"bytes\": %d}", $2, $1 }
                END { print "\n" }'
        printf '  ]\n'
        printf '}\n'
    } > "$report_tmp"

    mv -f "$report_tmp" "$report_json"
    chown root:www-data "$report_json"
    chmod 640 "$report_json"
    log "INFO: report written, $total_files file(s) in $SHARED_PATH"
}

# Escape a value for a JSON string
json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    printf '%s' "${value//\"/\\\"}"
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "smbreport start..."

load_conf "$smbstack_env"

if [ -z "${SHARED_PATH:-}" ]; then
    log "ERROR: SHARED_PATH not set in $(basename "$smbstack_env") -- abort"
    exit 1
fi

if [ ! -d "$SHARED_PATH" ]; then
    log "ERROR: shared folder '$SHARED_PATH' does not exist -- abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

case "${1:-}" in
    install)   register_cron ;;
    uninstall) deregister_cron ;;
    "")        build_report ;;
    *)         echo "Usage: $0 [install|uninstall]" >&2; exit 1 ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "smbreport done at: $(date '+%Y-%m-%d %H:%M:%S')"
