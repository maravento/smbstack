#!/bin/bash
# maravento.com
#
################################################################################
#
# smbreport -- disk usage report for smbstack
#
# DESCRIPTION:
# Walks the shared folder and writes the JSON report the web panel reads.
# Requires root.
#
# USAGE:
# sudo bash smbreport.sh            Build the report now
# sudo bash smbreport.sh install    Register the daily cron entry
# sudo bash smbreport.sh uninstall  Remove the cron entry (keeps the report)
#
# LOG: /var/log/smbstack.log
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
for dep_pkg in findutils coreutils util-linux cron php-cli; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: missing dependency '$dep_pkg' -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

smbstack_env="/etc/smbstack/smbstack.env"
installed_path="/etc/smbstack/tools/$(basename "$0")"
report_json="/var/www/smbstack/web/smbreport.json"
top_rows=30
top_files=50

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
    local total_files report_tmp
    report_tmp=$(mktemp)
    trap 'rm -f "$report_tmp"' RETURN

    # A file name may contain any byte except NUL and the slash, so the
    # inventory is NUL-delimited and php writes the JSON.
    export SHARED_PATH TOP_ROWS="$top_rows" TOP_FILES="$top_files"

    # .recycle is pruned, not filtered afterwards: its paths must never reach
    # the report, which is the same rule smbshared.php and smbweb.conf apply
    if ! find "$SHARED_PATH" -name .recycle -prune -o -type f -printf '%s\0%p\0' \
        2>/dev/null \
        | php -r '
            $data = stream_get_contents(STDIN);
            $parts = explode("\0", $data);
            $pairs = intdiv(count($parts), 2);
            $rows = array();
            for ($i = 0; $i < $pairs; $i++) {
                $rows[] = array((float) $parts[$i * 2], $parts[$i * 2 + 1]);
            }
            $total_bytes = 0.0;
            $by_ext = array();
            $by_dir = array();
            foreach ($rows as $row) {
                list($size, $path) = $row;
                $total_bytes += $size;
                $name = basename($path);
                $dot = strrpos($name, ".");
                $ext = ($dot === false || $dot === 0) ? "(none)"
                    : strtolower(substr($name, $dot + 1));
                if (!isset($by_ext[$ext])) { $by_ext[$ext] = array(0.0, 0); }
                $by_ext[$ext][0] += $size;
                $by_ext[$ext][1]++;
                $dir = dirname($path);
                if (!isset($by_dir[$dir])) { $by_dir[$dir] = array(0.0, 0); }
                $by_dir[$dir][0] += $size;
                $by_dir[$dir][1]++;
            }
            $top = function ($map, $limit, $label) {
                uasort($map, function ($a, $b) { return $b[0] <=> $a[0]; });
                $out = array();
                foreach (array_slice($map, 0, $limit, true) as $key => $val) {
                    $out[] = array($label => $key, "files" => $val[1],
                        "bytes" => (int) $val[0]);
                }
                return $out;
            };
            usort($rows, function ($a, $b) { return $b[0] <=> $a[0]; });
            $files = array();
            foreach (array_slice($rows, 0, (int) getenv("TOP_FILES")) as $row) {
                $files[] = array("path" => $row[1], "bytes" => (int) $row[0]);
            }
            $report = array(
                "generated" => date("Y-m-d H:i:s"),
                "folder" => getenv("SHARED_PATH"),
                "total_files" => count($rows),
                "total_bytes" => (int) $total_bytes,
                "extensions" => $top($by_ext, (int) getenv("TOP_ROWS"), "name"),
                "folders" => $top($by_dir, (int) getenv("TOP_ROWS"), "path"),
                "files" => $files,
            );
            $json = json_encode($report, JSON_PRETTY_PRINT
                | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
            if ($json === false) { exit(1); }
            echo $json, "\n";
            exit(0);
        ' > "$report_tmp"; then
        log "ERROR: report not built, previous one kept -- alert"
        return 1
    fi

    mv -f "$report_tmp" "$report_json"
    chown root:www-data "$report_json"
    chmod 640 "$report_json"
    total_files=$(grep -m1 '"total_files"' "$report_json" | tr -dc '0-9')
    log "INFO: report written, $total_files file(s) in $(basename "$SHARED_PATH")"
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
            SHARED_PATH)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

# LOAD
load_conf "$smbstack_env" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
for env_key in SHARED_PATH; do
    if ! grep -q "^${env_key}=" "$smbstack_env"; then
        key_errors+=("$env_key missing line")
    elif [[ -z "${!env_key:-}" ]]; then
        key_errors+=("$env_key not set")
    fi
done
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "ERROR: $key_error"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$smbstack_env") -- abort"
    exit 1
fi
unset key_errors key_error env_key

# KEY GUARD
# The whole report is built by walking this path, so a value that no longer
# matches the filesystem produces an empty report instead of an error.
if [ ! -d "$SHARED_PATH" ]; then
    log "ERROR: shared folder '$SHARED_PATH' does not exist -- abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "smbreport start..."

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
