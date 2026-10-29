#!/bin/bash
# maravento.com
#
################################################################################
#
# smbsetup -- installer for smbstack
# FILE: smbsetup.sh
#
# USAGE:
# sudo bash smbsetup.sh --install      Fresh install
# sudo bash smbsetup.sh --update       Refresh code and permissions
# sudo bash smbsetup.sh --uninstall    Remove smbstack
# sudo bash smbsetup.sh --status       Report the current state
# sudo bash smbsetup.sh                Interactive menu
#
# LOG: smbsetup.log, in this script's directory
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
log_file="${script_dir}/smbsetup.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$msg" >&2; else echo "$msg"; fi
}
info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err()  { log "ERROR: $*"; }
abort() { err "$*"; exit 1; }

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
    abort "no local user; create one with sudo access -abort"
fi
info "using local user: $local_user"

# dependencies
for dep_pkg in apache2-utils libapache2-mod-php php logrotate acl openssl cron iproute2 sudo systemd util-linux zip python3 inotify-tools procps coreutils findutils sed grep; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null)" != *"ok installed"* ]]; then
        abort "'$dep_pkg' is not installed -abort"
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

acl_dir="$script_dir/acl"
conf_dir="$script_dir/conf"
tools_dir="$script_dir/tools"
web_dir="$script_dir/web"
smbstack_www="/var/www/smbstack"
smbstack_web="$smbstack_www/web"
smbstack_etc="/etc/smbstack"
smbstack_tools="$smbstack_etc/tools"
smbstack_acl="$smbstack_etc/acl"
smbstack_env="$smbstack_etc/smbstack.env"

# validation -- one variable per thing validated; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# UPDATE CHECKS
update_error() {
    if declare -F err >/dev/null; then
        err "$* -abort"
    else
        log "ERROR: $* -abort"
    fi
    exit 1
}

update_reset() {
    update_cron_file="$1"
    update_files=()
    update_jobs=()
    update_services=()
    update_stopped_services=()
    update_daemons=()
    update_copying=0
    update_cron_paused=0
    update_cron_existed=0
    update_cron_already_paused=0
}

update_file() {
    update_files+=("$1" "$2" "$3" "$4")
    case "$2" in *.sh|*.py|*.pl) update_jobs+=("$2") ;; esac
}

update_target() {
    update_files+=("" "$1" "${2:-644}" "${3:-root:root}")
}

update_preflight() {
    command -v python3 >/dev/null 2>&1 || update_error "python3 is required for update checks"
    local check_message
    if check_message=$(python3 - "${update_files[@]}" <<'UPDATE_PY'
import array, errno, fcntl, os, stat, sys, tempfile
items = [sys.argv[i:i + 4] for i in range(1, len(sys.argv), 4)]
space, probes = {}, set()
def fail(message):
    print(message)
    raise SystemExit(1)
def flags(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        try:
            value = array.array('L', [0])
            try:
                fcntl.ioctl(fd, 0x80086601, value, True)
            except OSError as exc:
                if exc.errno not in (errno.ENOTTY, errno.EOPNOTSUPP, errno.EINVAL):
                    raise
            else:
                if value[0] & 0x30:
                    protection = []
                    if value[0] & 0x10:
                        protection.append('immutable')
                    if value[0] & 0x20:
                        protection.append('append-only')
                    fail(os.path.basename(path) + ' is ' + ' and '.join(protection))
        finally:
            os.close(fd)
    except OSError as exc:
        fail(exc.strerror.lower() + ': ' + os.path.basename(path))
for source, target, mode, owner in items:
    if source:
        try:
            st = os.lstat(source)
            if not stat.S_ISREG(st.st_mode):
                fail('source is not a file: ' + os.path.basename(source))
            with open(source, 'rb') as stream:
                stream.read(1)
        except OSError as exc:
            fail('cannot read source: ' + os.path.basename(source))
for source, target, mode, owner in items:
    target = os.path.abspath(target)
    directory = mode.startswith('d')
    try:
        parent = target if directory else os.path.dirname(target)
        if os.path.lexists(target):
            st = os.lstat(target)
            if (directory and not stat.S_ISDIR(st.st_mode)) or (not directory and not stat.S_ISREG(st.st_mode)):
                fail(('dst is not a folder: ' if directory else 'dst is not a file: ') + os.path.basename(target))
            flags(target)
            if not directory:
                fd = os.open(target, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                finally:
                    os.close(fd)
        while not os.path.exists(parent):
            if os.path.lexists(parent):
                fail('folder is a symbolic link: ' + parent)
            parent = os.path.dirname(parent)
        if not os.path.isdir(parent):
            fail('not a folder: ' + parent)
        current = parent
        while current != '/':
            if os.path.islink(current):
                fail('folder is a symbolic link: ' + current)
            flags(current)
            current = os.path.dirname(current)
        fs = os.statvfs(parent)
        if fs.f_flag & os.ST_RDONLY:
            fail('filesystem is read-only: ' + parent)
        if parent not in probes:
            fd, probe = tempfile.mkstemp(prefix='update-check-', dir=parent)
            try:
                os.write(fd, b'update check\n')
                os.fsync(fd)
            finally:
                os.close(fd)
                os.unlink(probe)
            probes.add(parent)
        device = os.stat(parent).st_dev
        required = os.stat(source).st_size if source else 4096
        needed, available, label = space.get(device, (0, fs.f_bavail * fs.f_frsize, parent))
        space[device] = (needed + required + 4096, available, label)
        if fs.f_favail == 0:
            fail('no free inodes for dst: ' + os.path.basename(target))
    except OSError as exc:
        fail('cannot write dst: ' + os.path.basename(target))
for needed, available, label in space.values():
    if available < needed:
        fail('not enough space to update: ' + label)
UPDATE_PY
    ); then
        :
    else
        update_error "$check_message"
    fi
}

update_backup() {
    [ -f "$1" ] && [ -r "$1" ] || update_error "backup script not readable: $(basename "$1")"
    bash "$1" || update_error "backup failed: $(basename "$1")"
}

update_begin() {
    export UPDATE_CRON_OWNER="$$"
    trap 'update_cleanup "$?"' EXIT
    local disabled="${update_cron_file}.update-disabled"
    [ ! -L "${update_cron_file}.lock" ] || update_error "invalid cron lock: $update_cron_file"
    (umask 077; : >> "${update_cron_file}.lock") || update_error "cannot open cron lock: $update_cron_file"
    exec 203>"${update_cron_file}.lock" || update_error "cannot open cron lock: $update_cron_file"
    flock -n 203 || update_error "cron file is being changed: $(basename "$update_cron_file")"
    if [ -e "$disabled" ] || [ -L "$disabled" ]; then
        [ -f "$disabled" ] && [ ! -L "$disabled" ] || update_error "invalid paused cron: $(basename "$disabled")"
        [ ! -e "$update_cron_file" ] || update_error "both active and paused cron exist: $(basename "$update_cron_file")"
        update_cron_already_paused=1
        update_cron_paused=1
    elif [ -e "$update_cron_file" ]; then
        mv -T -- "$update_cron_file" "$disabled" || update_error "cannot pause cron: $update_cron_file"
        update_cron_existed=1
        update_cron_paused=1
    else
        (umask 077; set -C; : > "$disabled") || update_error "cannot pause cron: $update_cron_file"
        update_cron_paused=1
    fi
    exec 203>&-
}

update_pids() {
    python3 - "$1" <<'UPDATE_PIDS'
import os, sys
wanted = os.path.realpath(sys.argv[1])
for entry in os.scandir('/proc'):
    if not entry.name.isdigit() or int(entry.name) == os.getpid():
        continue
    try:
        with open(entry.path + '/cmdline', 'rb') as stream:
            args = [os.fsdecode(value) for value in stream.read().split(b'\0') if value]
        if args and any(os.path.realpath(value) == wanted for value in args if value.startswith('/')):
            print(entry.name)
    except (OSError, ValueError):
        continue
UPDATE_PIDS
}

update_wait() {
    local script="$1" pids attempt
    for attempt in {1..30}; do
        pids=$(update_pids "$script") || update_error "cannot inspect processes: $(basename "$script")"
        [ -z "$pids" ] && return 0
        sleep 1
    done
    update_error "process still running: $(basename "$script")"
}

update_stop_daemon() {
    local script="$1" pids
    pids=$(update_pids "$script") || update_error "cannot inspect processes: $script"
    if [ -n "$pids" ]; then
        update_daemons+=("$script")
        bash "$script" --stop || update_error "cannot stop daemon: $script"
        update_wait "$script"
    fi
}

update_stop_service() {
    local unit="$1" state load_state
    load_state=$(systemctl show -p LoadState --value "$unit") || update_error "cannot inspect service: $unit"
    [ "$load_state" != not-found ] || return 0
    state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect service: $unit"
    case "$state" in
        active|reloading|activating|deactivating) update_services+=("$unit") ;;
        inactive|failed) ;;
        *) update_error "unexpected service state: $unit ($state)" ;;
    esac
    update_stopped_services+=("$unit")
    systemctl stop "$unit" || update_error "cannot stop service: $unit"
    state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect stopped: $unit"
    [ "$state" = inactive ] || {
        log "ERROR: $unit state: $state"
        update_error "$unit did not stop"
    }
}

update_wait_jobs() {
    local script unit state
    for script in "${update_jobs[@]}"; do
        update_wait "$script"
    done
    for unit in "${update_stopped_services[@]}"; do
        state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect stopped: $unit"
        [ "$state" = inactive ] || update_error "service restarted in update: $unit"
    done
}

update_apply() {
    update_preflight
    update_copying=1
    local i source target mode owner
    for ((i=0; i<${#update_files[@]}; i+=4)); do
        source="${update_files[i]}"
        target="${update_files[i+1]}"
        mode="${update_files[i+2]}"
        owner="${update_files[i+3]}"
        if [[ "$mode" == d* ]]; then
            install -d -m "${mode#d}" -o "${owner%:*}" -g "${owner#*:}" -- "$target" \
                || update_error "cannot prepare directory: $target"
            continue
        fi
        if [ -z "$source" ]; then
            if [ ! -d "$(dirname "$target")" ]; then
                install -d -m 755 -o root -g root -- "$(dirname "$target")" \
                    || update_error "cannot prepare destination parent: $(basename "$target")"
            fi
            continue
        fi
        install -D -m "$mode" -o "${owner%:*}" -g "${owner#*:}" -- "$source" "$target" \
            || update_error "cannot replace file: $(basename "$target")"
        cmp -s -- "$source" "$target" || {
            local compared_file
            compared_file=$(basename "$target")
            if (( ${#compared_file} <= 19 )); then
                update_error "src and dst do not match: $compared_file"
            fi
            log "ERROR: src and dst: $compared_file"
            update_error "src and dst do not match"
        }
        info "updated $(basename "$target")"
    done
}

update_resume() {
    local unit script state
    for unit in "${update_services[@]}"; do
        systemctl start "$unit" || update_error "cannot start service: $unit"
        state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect started: $unit"
        [ "$state" = active ] || {
            log "ERROR: $unit state: $state"
            update_error "$unit did not start"
        }
    done
    for script in "${update_daemons[@]}"; do
        bash "$script" --start || update_error "cannot start daemon: $script"
        [ -n "$(update_pids "$script")" ] || update_error "daemon did not start: $script"
    done
}

update_finish() {
    update_resume
    rm -f -- "${update_cron_file}.update-disabled" || update_error "cannot finish cron update: $(basename "$update_cron_file")"
    trap - EXIT
    unset UPDATE_CRON_OWNER
}

update_cleanup() {
    local status="$1" unit script
    trap - EXIT
    if (( update_copying == 0 )); then
        for unit in "${update_services[@]}"; do
            systemctl start "$unit" || warn "cannot resume $unit -alert"
        done
        for script in "${update_daemons[@]}"; do
            bash "$script" --start || warn "cannot resume $(basename "$script") -alert"
        done
        if (( update_cron_paused && ! update_cron_already_paused )); then
            if (( update_cron_existed )); then
                mv -T -- "${update_cron_file}.update-disabled" "$update_cron_file" \
                    || warn "cannot restore paused cron -alert"
            else
                rm -f -- "${update_cron_file}.update-disabled" || warn "cannot clear paused cron -alert"
            fi
        fi
    else
        if rm -f -- "$update_cron_file"; then
            warn "update failed; cron remains disabled -alert"
        else
            warn "cannot keep project cron paused -alert"
        fi
        for unit in "${update_services[@]}"; do
            systemctl stop "$unit" || warn "cannot keep $unit stopped -alert"
        done
        for script in "${update_daemons[@]}"; do
            bash "$script" --stop || warn "cannot keep $(basename "$script") stopped -alert"
        done
    fi
    (( status != 0 )) || status=1
    exit "$status"
}

# CRON FILE
# Publish the complete project schedule after preparing it successfully.
cron_d_write() (
    local cron_file="/etc/cron.d/smbstack"
    local cron_tmp

    [ "$#" -gt 0 ] || return 1
    [ ! -L "${cron_file}.lock" ] || return 1
    (umask 077; : >> "${cron_file}.lock") || return 1
    exec 201>"${cron_file}.lock" || return 1
    flock -x 201 || return 1
    if [ -e "${cron_file}.update-disabled" ] && [ "${UPDATE_CRON_OWNER:-}" != "$$" ]; then
        return 1
    fi
    [ ! -L "$cron_file" ] || return 1
    [ ! -e "$cron_file" ] || [ -f "$cron_file" ] || return 1

    cron_tmp=$(mktemp "${cron_file}.XXXXXX") || return 1
    trap 'rm -f -- "$cron_tmp"' EXIT
    {
        printf '%s\n' '# Managed by the project installer; manual changes are replaced.'
        printf '%s\n' 'SHELL=/bin/bash' 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        printf '%s\n' "$@"
    } > "$cron_tmp" || return 1
    chmod 644 "$cron_tmp" && chown root:root "$cron_tmp" || return 1
    mv -fT -- "$cron_tmp" "$cron_file" || return 1
)

# PROJECT SCHEDULE
# Publish all tasks defined by this project
register_project_cron() {
    local shared_path="$1"
    local -a project_cron_lines=(
        "@weekly root find \"$shared_path/.recycle/\" -depth -mindepth 1 -mtime +6 -delete >/dev/null 2>&1"
        "@daily root find /var/www/smbstack/.size_cache -name \"*.cache\" -mmin +60 -delete >/dev/null 2>&1"
        "*/5 * * * * root $smbstack_tools/smbload.sh"
        "@monthly root $smbstack_tools/smbbk.sh"
        "0 3 * * * root $smbstack_tools/smbreport.sh"
    )
    if grep -q '^WATCH_LIMIT_GB=' "$smbstack_env" && grep -q '^WATCH_EXCLUDE=' "$smbstack_env"; then
        project_cron_lines+=("@reboot root $smbstack_tools/smbwatch.sh --start")
    fi
    cron_d_write "${project_cron_lines[@]}"
}

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            abort "Samba package installation failed -abort"
        fi
        info "Samba packages: retry $((attempt + 1))/$max_attempts"
        attempt=$((attempt + 1))
        sleep 10
    done
}

# checking conflicting pre-installed packages
check_conflicts() {
    local role="$1"; shift
    local found=()
    for dep_pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q "ok installed"; then
            found+=("$dep_pkg")
        fi
    done
    if [ "${#found[@]}" -gt 0 ]; then
        for dep_pkg in "${found[@]}"; do
            warn "conflicting $role: $dep_pkg -alert"
        done
        abort "remove them with apt purge -abort"
    fi
}

# port in use
check_port() {
    local proto="$1" port="$2" role="$3"
    if [ -n "$(ss -lnH "--${proto,,}" "sport = :$port" 2>/dev/null)" ]; then
        err "${proto^^} port $port in use by another $role"
        abort "stop that service before installing -abort"
    fi
}

check_repo() {
    local missing_dir=0
    for repo_subdir in "$acl_dir" "$conf_dir" "$tools_dir" "$web_dir"; do
        if [ ! -d "$repo_subdir" ] || [ -z "$(ls -A "$repo_subdir" 2>/dev/null)" ]; then
            missing_dir=1
            break
        fi
    done
    if [ "$missing_dir" -eq 1 ]; then
        echo ""
        err "repository files not found"
        err "clone it from github.com/maravento/smbstack -abort"
        echo ""
        exit 1
    fi
}
check_repo

# shared folder setup
select_shared_folder() {
    echo ""
    echo "Shared folder setup"
    echo "-------------------"
    while true; do
        read -p "Enter shared folder name [shared]: " folder_answer
        folder_answer="${folder_answer:-shared}"
        if [[ "$folder_answer" =~ [^a-zA-Z0-9_-] ]]; then
            info "invalid folder name"
            info "use letters, numbers, hyphens, underscores -retry"
            folder_answer=""
        else
            break
        fi
    done
    share_dir="/home/$local_user/$folder_answer"
    setfacl -m u:www-data:--x "/home/$local_user" \
        || warn "cannot set ACL on $(basename "/home/$local_user") -alert"
    setfacl -m u:smbguest:--x "/home/$local_user" \
        || warn "cannot set ACL on $(basename "/home/$local_user") -alert"

    if [ -d "$share_dir" ]; then
        actual_owner=$(stat -c "%U" "$share_dir")
        actual_group=$(stat -c "%G" "$share_dir")
        actual_mode=$(stat -c "%a" "$share_dir")

        if [ "$actual_owner" != "$local_user" ] || [ "$actual_group" != "sambashare" ]; then
            chown "$local_user":sambashare "$share_dir" \
                || warn "cannot set owner and group: $(basename "$share_dir") -alert"
        fi

        if [ "$actual_mode" != "755" ]; then
            chmod 755 "$share_dir" \
                || warn "cannot set permissions on $(basename "$share_dir") -alert"
        fi

        while IFS= read -r shared_subdir; do
            dir_owner=$(stat -c "%U" "$shared_subdir")
            dir_group=$(stat -c "%G" "$shared_subdir")
            dir_mode=$(stat -c "%a" "$shared_subdir")
            if [ "$dir_owner" != "$local_user" ] || [ "$dir_group" != "sambashare" ]; then
                chown "$local_user":sambashare "$shared_subdir" \
                    || warn "cannot set owner and group: $(basename "$shared_subdir") -alert"
            fi
            if [ "$dir_mode" != "2775" ]; then
                chmod 2775 "$shared_subdir" \
                    || warn "cannot set permissions on $(basename "$shared_subdir") -alert"
            fi
        done < <(find "$share_dir" -mindepth 1 -path "$share_dir/.recycle" -prune -o -type d -print)

        while IFS= read -r shared_file; do
            file_owner=$(stat -c "%U" "$shared_file")
            file_group=$(stat -c "%G" "$shared_file")
            file_mode=$(stat -c "%a" "$shared_file")
            if [ "$file_owner" != "$local_user" ] || [ "$file_group" != "sambashare" ]; then
                chown "$local_user":sambashare "$shared_file" \
                    || warn "cannot set owner and group: $(basename "$shared_file") -alert"
            fi
            if [ "$file_mode" != "664" ]; then
                chmod 664 "$shared_file" \
                    || warn "cannot set permissions on $(basename "$shared_file") -alert"
            fi
        done < <(find "$share_dir" -mindepth 1 -path "$share_dir/.recycle" -prune -o -type f -print)

        if ! getfacl "$share_dir" 2>/dev/null | grep -q "user:www-data:r-x"; then
            setfacl -m u:www-data:r-x "$share_dir" \
                || warn "cannot set ACL on $(basename "$share_dir") -alert"
        fi
        # root ACL: mask r-x (blocks group write on root), default mask rwx (allows group write in subdirs)
        setfacl -m mask::r-x "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        setfacl -d -m g:sambashare:rwx "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        setfacl -d -m mask::rwx "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        # recycle bin
        # Each channel is precreated and owned by its own writer, so no SMB
        # client needs write access on .recycle itself. The direct mask blocks
        # group write there; the default mask keeps it inside each channel.
        mkdir -p "$share_dir/.recycle"
        chown www-data:www-data "$share_dir/.recycle" \
            || warn "cannot set owner and group: $(basename "$share_dir/.recycle") -alert"
        chmod 755 "$share_dir/.recycle" \
            || warn "cannot set permissions on $(basename "$share_dir/.recycle") -alert"
        install -d -o smbguest -g sambashare -m 2775 "$share_dir/.recycle/smbguest"
        install -d -o www-data -g www-data -m 775 "$share_dir/.recycle/www-data"
        setfacl -m g:sambashare:rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -d -m g:sambashare:rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -m mask::r-x "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -d -m mask::rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -R -x g:sambashare "$share_dir/.recycle/www-data" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle/www-data") -alert"
        setfacl -R -d -x g:sambashare "$share_dir/.recycle/www-data" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle/www-data") -alert"
    else
        sudo -u "$local_user" mkdir -p "$share_dir"
        chmod 755 "$share_dir" \
            || warn "cannot set permissions on $(basename "$share_dir") -alert"
        chown "$local_user":sambashare "$share_dir" \
            || warn "cannot set owner and group: $(basename "$share_dir") -alert"
        sudo -u "$local_user" mkdir -p "$share_dir/DEMO"
        sudo -u "$local_user" bash -c "echo 'this is a demo file' > '$share_dir/DEMO/demo.txt'"
        while IFS= read -r shared_subdir; do
            if chown "$local_user":sambashare "$shared_subdir"; then
                chmod 2775 "$shared_subdir" \
                    || warn "cannot set permissions on $(basename "$shared_subdir") -alert"
            else
                warn "cannot set owner and group: $(basename "$shared_subdir") -alert"
            fi
        done < <(find "$share_dir" -mindepth 1 -type d -print)
        while IFS= read -r shared_file; do
            if chown "$local_user":sambashare "$shared_file"; then
                chmod 664 "$shared_file" \
                    || warn "cannot set permissions on $(basename "$shared_file") -alert"
            else
                warn "cannot set owner and group: $(basename "$shared_file") -alert"
            fi
        done < <(find "$share_dir" -mindepth 1 -type f -print)
        setfacl -m u:www-data:r-x "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        setfacl -m mask::r-x "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        setfacl -d -m g:sambashare:rwx "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        setfacl -d -m mask::rwx "$share_dir" \
            || warn "cannot set ACL on $(basename "$share_dir") -alert"
        # recycle bin
        # Each channel is precreated and owned by its own writer, so no SMB
        # client needs write access on .recycle itself. The direct mask blocks
        # group write there; the default mask keeps it inside each channel.
        mkdir -p "$share_dir/.recycle"
        chown www-data:www-data "$share_dir/.recycle" \
            || warn "cannot set owner and group: $(basename "$share_dir/.recycle") -alert"
        chmod 755 "$share_dir/.recycle" \
            || warn "cannot set permissions on $(basename "$share_dir/.recycle") -alert"
        install -d -o smbguest -g sambashare -m 2775 "$share_dir/.recycle/smbguest"
        install -d -o www-data -g www-data -m 775 "$share_dir/.recycle/www-data"
        setfacl -m g:sambashare:rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -d -m g:sambashare:rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -m mask::r-x "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -d -m mask::rwx "$share_dir/.recycle" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle") -alert"
        setfacl -R -x g:sambashare "$share_dir/.recycle/www-data" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle/www-data") -alert"
        setfacl -R -d -x g:sambashare "$share_dir/.recycle/www-data" \
            || warn "cannot set ACL on $(basename "$share_dir/.recycle/www-data") -alert"
    fi

    echo "Shared folder: $share_dir"
    echo ""
}

# IFACES
# List network interfaces other than loopback
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

# IPV4 INTERFACES
# Offer only interfaces with an active link and configured global IPv4
list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

# LAN SELECTION
# Select an existing interface and one of its configured IPv4 addresses
choose_lan_interface() {
    local preset_iface="${1:-}"
    local iface_name iface_choice iface_index iface_addrs iface_state
    local -a lan_candidates=()
    while IFS= read -r iface_name; do
        lan_candidates+=("$iface_name")
    done < <(list_ipv4_ifaces)
    if [ -n "$preset_iface" ]; then
        for iface_name in "${lan_candidates[@]}"; do
            if [ "$preset_iface" = "$iface_name" ]; then
                lan_iface_answer="$preset_iface"
                return 0
            fi
        done
        log "ERROR: LAN must be an active interface with IPv4 -abort"
        exit 1
    fi
    (( ${#lan_candidates[@]} > 0 )) || {
        log "ERROR: no LAN interface available -abort"
        exit 1
    }
    if (( ${#lan_candidates[@]} == 1 )); then
        lan_iface_answer="${lan_candidates[0]}"
        return 0
    fi
    echo "Available LAN interfaces:"
    for iface_index in "${!lan_candidates[@]}"; do
        iface_name="${lan_candidates[$iface_index]}"
        iface_state=$(ip -br link show "$iface_name" | awk '{print $2}')
        iface_addrs=$(ip -4 -o addr show dev "$iface_name" scope global | awk '{print $4}' | paste -sd' ')
        printf ' [%d] %s (%s, %s)\n' "$((iface_index + 1))" "$iface_name" "$iface_state" "${iface_addrs:-no IPv4}"
    done
    while true; do
        read -r -p "Select LAN Interface [1-${#lan_candidates[@]}]: " iface_choice || {
            log "ERROR: cannot read LAN interface selection -abort"
            exit 1
        }
        if [[ "$iface_choice" =~ $UH_UINT ]] && [ "${#iface_choice}" -le 5 ] \
           && [ "$iface_choice" -ge 1 ] && [ "$iface_choice" -le "${#lan_candidates[@]}" ]; then
            lan_iface_answer="${lan_candidates[$((iface_choice - 1))]}"
            return 0
        fi
        log "INFO: invalid LAN interface selection -retry"
    done
}

read_lan_ipv4() {
    local selected_iface="$1" preset_ip="${2:-}" ipv4_choice ipv4_index candidate_cidr
    local -a lan_addresses=()
    mapfile -t lan_addresses < <(ip -4 -o addr show dev "$selected_iface" scope global | awk '{print $4}')
    (( ${#lan_addresses[@]} > 0 )) || {
        log "ERROR: LAN '$selected_iface' has no IPv4 address -abort"
        exit 1
    }
    for candidate_cidr in "${lan_addresses[@]}"; do
        [[ "$candidate_cidr" =~ $UH_CIDR ]] || {
            log "ERROR: LAN '$selected_iface' has invalid IPv4/prefix -abort"
            exit 1
        }
    done
    if [ -n "$preset_ip" ]; then
        for candidate_cidr in "${lan_addresses[@]}"; do
            if [ "${candidate_cidr%/*}" = "$preset_ip" ]; then
                lan_cidr_answer="$candidate_cidr"
                return 0
            fi
        done
        log "ERROR: requested IPv4 is not configured on LAN -abort"
        exit 1
    fi
    if (( ${#lan_addresses[@]} == 1 )); then
        lan_cidr_answer="${lan_addresses[0]}"
        return 0
    fi
    echo "IPv4 addresses on LAN '$selected_iface':"
    for ipv4_index in "${!lan_addresses[@]}"; do
        printf ' [%d] %s\n' "$((ipv4_index + 1))" "${lan_addresses[$ipv4_index]}"
    done
    while true; do
        read -r -p "Select LAN IPv4 number: " ipv4_choice || {
            log "ERROR: cannot read LAN IPv4 selection -abort"
            exit 1
        }
        if [[ "$ipv4_choice" =~ $UH_UINT ]] && [ "${#ipv4_choice}" -le 5 ] \
           && [ "$ipv4_choice" -ge 1 ] && [ "$ipv4_choice" -le "${#lan_addresses[@]}" ]; then
            lan_cidr_answer="${lan_addresses[$((ipv4_choice - 1))]}"
            return 0
        fi
        log "INFO: invalid LAN IPv4 selection -retry"
    done
}

# ------------------------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------------------------

check_already_installed() {
    local already_installed=0
    local skip_reasons=""

    if pdbedit -L 2>/dev/null | grep -q ":"; then
        already_installed=1
        skip_reasons+=" - Samba users already registered (pdbedit)\n"
    fi

    if [ -f "$smbstack_env" ]; then
        already_installed=1
        skip_reasons+=" - smbstack.env already exists: $smbstack_env\n"
    fi

    if [ -f "/etc/samba/smb.conf" ]; then
        existing_share=""
        [ -f "$smbstack_env" ] && { load_smbstack_env "$smbstack_env" "$env_keys"; existing_share="${SHARED_NAME:-}"; }
        if [ -n "$existing_share" ] && grep -q "\[${existing_share}\]" /etc/samba/smb.conf 2>/dev/null; then
            already_installed=1
            skip_reasons+=" - smb.conf already configured: /etc/samba/smb.conf\n"
        fi
    fi

    if [ "$already_installed" -eq 1 ]; then
        echo ""
        err "Samba is already installed"
        err "update with: sudo bash smbsetup.sh --update -abort"
        echo ""
        printf "%b" "$skip_reasons"
        echo ""
        exit 1
    fi
}

# APACHE LOGROTATE
# Apache keeps 14 rotations by default; the projects keep 7
set_apache_logrotate() {
    local apache_rotate="/etc/logrotate.d/apache2"
    [ -f "$apache_rotate" ] || { warn "apache2 has no logrotate file -alert"; return 0; }
    if grep -qE '^[[:space:]]*rotate[[:space:]]+7$' "$apache_rotate"; then
        info "${apache_rotate#/etc/} already rotate 7 -skip"
        return 0
    fi
    cp -f "$apache_rotate"{,.bak} &>/dev/null || true
    sed -i -E 's/^([[:space:]]*)rotate[[:space:]]+[0-9]+$/\1rotate 7/' "$apache_rotate"
    if grep -qE '^[[:space:]]*rotate[[:space:]]+7$' "$apache_rotate"; then
        info "${apache_rotate#/etc/} set to rotate 7 -fixed"
    else
        warn "cannot set rotate 7 in ${apache_rotate#/etc/} -alert"
    fi
}

install_project_logrotate() {
    local rotate_file="/etc/logrotate.d/smbstack"
    local project_log="/var/log/smbstack.log"
    if [ ! -f "$project_log" ]; then
        touch "$project_log" || return 1
    fi
    chown root:adm "$project_log" || return 1
    chmod 640 "$project_log" || return 1
    cat > "$rotate_file" <<EOF
$project_log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF
    [ "$?" -eq 0 ] || return 1
    chown root:root "$rotate_file" || return 1
    chmod 644 "$rotate_file" || return 1
    info "updated $rotate_file"
    set_apache_logrotate
}

do_install() {
    check_already_installed

    # dependency check
    check_conflicts "web server" nginx lighttpd caddy
    check_conflicts "SMB server" ksmbd-tools
    check_conflicts "syslog" syslog-ng
    check_port tcp 3092 "web interface"

    if ! systemctl is-active --quiet apache2; then
        err "apache2 is not running"
        abort "start it with: systemctl start apache2 -abort"
    fi

    if ! systemctl is-active --quiet rsyslog; then
        err "rsyslog is not running"
        abort "start it with: systemctl start rsyslog -abort"
    fi

    # enable required apache modules
    a2enmod -q headers mime rewrite

    # samba packages
    retry_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y samba samba-common samba-common-bin smbclient winbind cifs-utils

    systemctl enable smbd.service
    systemctl enable winbind.service

    groupadd -f sambashare
    usermod -aG sambashare "$local_user"

    # smbguest: dedicated unprivileged samba guest user
    if ! id smbguest &>/dev/null; then
        useradd -r -s /bin/false smbguest
    fi
    usermod -aG sambashare smbguest
    # create samba password for smbguest (random, not used interactively)
    smb_guest_pass=$(openssl rand -base64 16)
    printf "%s\n%s\n" "$smb_guest_pass" "$smb_guest_pass" | smbpasswd -a -s smbguest
    unset smb_guest_pass
    usermod -a -G sambashare www-data

    select_shared_folder

    mkdir -p /var/lib/samba/usershares
    chmod 1775 /var/lib/samba/usershares/
    mkdir -p /var/log/samba

    cp -f /lib/systemd/system/smbd.service{,.bak} &>/dev/null
    sed -i 's/ \$SMBDOPTIONS//' /lib/systemd/system/smbd.service

    # samba web viewer and tools
    touch /var/log/samba/log.samba /var/log/samba/log.audit
    chown root:adm /var/log/samba/log.samba /var/log/samba/log.audit
    chmod 660 /var/log/samba/log.samba /var/log/samba/log.audit

    # smbwatch log
    touch /var/log/smbwatch.log
    chown root:root /var/log/smbwatch.log
    chmod 640 /var/log/smbwatch.log

    mkdir -p "$smbstack_web"
    mkdir -p "$smbstack_www/.size_cache"
    chown www-data:www-data "$smbstack_www/.size_cache"
    chmod 700 "$smbstack_www/.size_cache"
    # every file in web/ is application code
    for web_file in "$web_dir"/*; do
        [ -f "$web_file" ] || continue
        cp -f "$web_file" "$smbstack_web/" || abort "cannot copy web files -abort"
    done
    if ! chmod -R 755 "$smbstack_web"; then
        abort "cannot set Samba web permissions -abort"
    fi
    if ! chown -R www-data:www-data "$smbstack_web"; then
        abort "cannot set Samba web owner and group -abort"
    fi

    # apache vhosts (both in smbweb.conf)
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    cp -f "$conf_dir/smbweb.conf" /etc/apache2/sites-available/smbweb.conf || abort "cannot deploy smbweb.conf -abort"
    a2ensite -q smbweb.conf

    # replace placeholders in deployed files (not in repo)
    for deploy_file in \
        /etc/apache2/sites-available/smbweb.conf \
        "$smbstack_web/smbaudit.html" \
        "$smbstack_web/smbapi.php" \
        "$smbstack_web/smbaudit-diagnostic.php" \
        "$smbstack_web/smbshared.php"; do
        [ -f "$deploy_file" ] || continue
        escaped_user=$(printf '%s' "$local_user" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" "$deploy_file"
        sed -i "s|compartida|$folder_answer|g" "$deploy_file"
    done

    # logrotate
    cp -f /etc/logrotate.d/samba{,.bak} &>/dev/null
    cat > /etc/logrotate.d/samba <<'EOF'
/var/log/samba/log.audit {
    weekly
    missingok
    rotate 7
    create 0660 root adm
    postrotate
        systemctl restart rsyslog > /dev/null 2>&1 || true
    endscript
    compress
    notifempty
}
/var/log/samba/log.samba {
    weekly
    missingok
    rotate 7
    postrotate
        systemctl reload smbd > /dev/null || true
    endscript
    compress
    notifempty
}
EOF

    # smbwatch logrotate
    cat > /etc/logrotate.d/smbwatch <<'EOF'
/var/log/smbwatch.log {
    weekly
    missingok
    rotate 7
    create 0640 root root
    compress
    notifempty
}
EOF

    # smb.conf
    prompt_smb_net_iface() {
        choose_lan_interface "${SMBSTACK_IFACE:-}"
        iface_answer="$lan_iface_answer"
        read_lan_ipv4 "$iface_answer"
        local iface_cidr iface_only iface_prefix o1 o2 o3 o4 ip_num mask_num net_num
        iface_cidr="$lan_cidr_answer"
        iface_only="${iface_cidr%/*}"
        iface_prefix="${iface_cidr#*/}"
        IFS=. read -r o1 o2 o3 o4 <<< "$iface_only"
        ip_num=$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
        mask_num=$(( 0xFFFFFFFF ^ ((1 << (32 - iface_prefix)) - 1) ))
        net_num=$(( ip_num & mask_num ))
        net_answer="$(( (net_num >> 24) & 255 )).$(( (net_num >> 16) & 255 )).$(( (net_num >> 8) & 255 )).$(( net_num & 255 ))/$iface_prefix"
        info "Samba network: $net_answer ($iface_answer)"
    }

    apply_smb_conf_placeholders() {
        local escaped_user
        escaped_user=$(printf '%s' "$local_user" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" /etc/samba/smb.conf
        sed -i "s|compartida|$folder_answer|g" /etc/samba/smb.conf
    }

    apply_smb_conf_interfaces() {
        sed -i "s|interfaces = .*|interfaces = 127.0.0.0/8 $net_answer $iface_answer|" /etc/samba/smb.conf \
            || warn "smb.conf: cannot set interfaces -alert"
        sed -i "s|hosts allow = .*|hosts allow = 127.0.0.1, $net_answer|" /etc/samba/smb.conf \
            || warn "smb.conf: cannot set hosts allow -alert"
    }

    if [ -f /etc/samba/smb.conf ]; then
        while true; do
            read -p "smb.conf already exists. Overwrite? (y/n) [n]: " overwrite_answer
            overwrite_answer="${overwrite_answer:-n}"
            case "$overwrite_answer" in
                [Yy])
                    cp -f /etc/samba/smb.conf{,.bak} \
                        && info "smb.conf backup saved as smb.conf.bak"
                    cp -f "$conf_dir/smb.conf" /etc/samba/smb.conf
                    apply_smb_conf_placeholders
                    prompt_smb_net_iface
                    apply_smb_conf_interfaces
                    break
                    ;;
                [Nn])
                    warn "smb.conf: existing configuration kept"
                    warn "smb.conf: add share, full_audit and recycle -alert"
                    prompt_smb_net_iface
                    break
                    ;;
                *)
                    info "answer y or n -retry"
                    ;;
            esac
        done
    else
        cp -f "$conf_dir/smb.conf" /etc/samba/smb.conf
        apply_smb_conf_placeholders
        prompt_smb_net_iface
        apply_smb_conf_interfaces
    fi

    # veto list required by the include line in smb.conf. Open per rules.md 14:
    # smbd's per-connection child reads the include as the authenticated user.
    install -d -m 755 -o root -g root "$smbstack_acl"
    install -m 644 -o root -g root "$acl_dir/commonveto.txt" \
        "$smbstack_acl/commonveto.txt"

    # rsyslog
    cp -f /etc/rsyslog.conf{,.bak} &>/dev/null
    sed -i -E 's/^(\s*(\$FileOwner|\$FileGroup|\$FileCreateMode|\$DirCreateMode|\$Umask|\$PrivDropToUser|\$PrivDropToGroup)\b.*)/#\1/' /etc/rsyslog.conf
    cp -f "$conf_dir/fullaudit.conf" /etc/rsyslog.d/fullaudit.conf
    chmod 644 /etc/rsyslog.d/fullaudit.conf
    chown root:root /etc/rsyslog.d/fullaudit.conf
    usermod -a -G adm www-data

    cp -f /etc/logrotate.d/rsyslog{,.bak} &>/dev/null
    grep -qE '^[[:space:]]*create 0644 syslog adm[[:space:]]*$' /etc/logrotate.d/rsyslog || \
        sed -i '/sharedscripts/a \ create 0644 syslog adm' /etc/logrotate.d/rsyslog
    grep -qE '^[[:space:]]*su syslog adm[[:space:]]*$' /etc/logrotate.d/rsyslog || \
        sed -i '/^{$/a \	su syslog adm' /etc/logrotate.d/rsyslog

    if ! logrotate -d /etc/logrotate.d/samba >/dev/null 2>&1; then
        warn "logrotate: samba config check failed -alert"
    fi

    # service watchdog
    mkdir -p "$smbstack_tools"
    if ! install -m 644 -o root -g root "$tools_dir/smbstackenv.sh" "$smbstack_tools/smbstackenv.sh"; then
        abort "cannot deploy smbstackenv.sh -abort"
    fi
    if ! { cp -f "$tools_dir"/*.sh "$smbstack_tools/" \
        && chmod +x "$smbstack_tools"/*.sh \
        && chmod 644 "$smbstack_tools/smbstackenv.sh"; }; then
        abort "cannot deploy tools -abort"
    fi

    systemctl daemon-reload

    detected_ip="${lan_cidr_answer%/*}"
    if ! [[ "$detected_ip" =~ $UH_IPV4 ]]; then
        err "no IPv4 address on $iface_answer"
        abort "check the interface and run again -abort"
    fi
    # Drop any prior Listen line for this port (a stale IP or a bare
    # "Listen 3092") before adding the current ones.
    sed -i -E "/^Listen [^[:space:]]*:3092\$/d; /^Listen 3092\$/d" /etc/apache2/ports.conf
    # Loopback only, for a local tunnel daemon like cloudflared, which
    # connects to Apache via 127.0.0.1 (see TRUSTED_PROXIES). Not
    # reachable from the LAN.
    echo "Listen 127.0.0.1:3092" >> /etc/apache2/ports.conf
    info "Port 3092 bound to 127.0.0.1"

    for apache_php_ini in /etc/php/*/apache2/php.ini; do
        [ -f "$apache_php_ini" ] || continue
        if ! { [ -f "${apache_php_ini}.bak" ] || cp -p "$apache_php_ini" "${apache_php_ini}.bak"; }; then
            echo "ERROR: cannot back up $apache_php_ini -abort" >&2
            exit 1
        fi
        if grep -Eq '^[[:space:]]*;*[[:space:]]*session\.upload_progress\.enabled[[:space:]]*=' "$apache_php_ini"; then
            sed -i 's/^[[:space:]]*;*[[:space:]]*session\.upload_progress\.enabled[[:space:]]*=.*/session.upload_progress.enabled = 0/' "$apache_php_ini" || {
                echo "ERROR: cannot edit $apache_php_ini -abort" >&2
                exit 1
            }
        else
            printf '\nsession.upload_progress.enabled = 0\n' >> "$apache_php_ini" || {
                echo "ERROR: cannot edit $apache_php_ini -abort" >&2
                exit 1
            }
        fi
    done

    if ! systemctl restart smbd winbind rsyslog apache2; then
        abort "restart smbd winbind rsyslog apache2 failed -abort"
    fi

    # create Samba account for local user
    samba_account="$local_user"
    printf "\n"
    info "Create Samba Password: $samba_account"
    printf "\n"
    while true; do
        read -s -p "Enter Samba password for $samba_account: " smb_pass; echo
        if [ "${#smb_pass}" -lt 8 ]; then
            echo "Password must be at least 8 characters. Try again"
            continue
        fi
        read -s -p "Confirm password: " smb_pass2; echo
        [ "$smb_pass" = "$smb_pass2" ] && break
        echo "Passwords do not match. Try again"
    done
    printf "%s\n%s\n" "$smb_pass" "$smb_pass" | smbpasswd -a -s "$samba_account"
    unset smb_pass smb_pass2

    # TRUSTED_PROXIES: used by web/smbshared.php to decide whether the
    # CF-Connecting-IP / X-Forwarded-For headers can be trusted when
    # logging the client IP for web operations (upload/mkdir/delete).
    # Set to 127.0.0.1 so that, if this host is ever reached through a
    # local tunnel (cloudflared or similar), the tunnel's own loopback
    # connection isn't logged as the "client" - the real visitor IP from
    # the forwarded header is used instead. For plain LAN access this has
    # no effect: REMOTE_ADDR is simply used as-is.
    proxy_list="127.0.0.1"

    # save install config
    install -d -m 755 -o root -g root "$smbstack_etc"
    cat > "$smbstack_env" <<ENV
# =============================================================================
# SMBstack
# /etc/smbstack/smbstack.env
# =============================================================================

# General
LOCAL_USER=$local_user

# Sharing
SHARED_NAME=$folder_answer
SHARED_PATH=$share_dir

# Network
SMB_NET=$net_answer
SMB_IFACE=$iface_answer
SERVER_IP=$detected_ip

# Samba
SMBNAME=$samba_account

# Logs
# MAX_LOG_LINES: max lines read from the current (non-rotated) audit log
# file per request, by both smbapi.php and smbaudit-diagnostic.php.
# NOTE: smbaudit.html's own fetch request uses a fixed limit of 50000 in
# its JS code, independent of this value -- raising MAX_LOG_LINES here does
# not change what the audit viewer UI requests.
MAX_LOG_LINES=50000

# Reports
# Changing these defaults is not recommended
SMBREPORT_TOP_ROWS=30
SMBREPORT_TOP_FILES=50

# Proxies
# TRUSTED_PROXIES: IPv4 address(es), comma-separated, whose REMOTE_ADDR
# is trusted to supply the real client IP via CF-Connecting-IP /
# X-Forwarded-For headers (used by web/smbshared.php for audit logging).
# Default 127.0.0.1 avoids logging the loopback connection of a local
# tunnel (if any) as the client. Safe to leave as-is for LAN-only use.
TRUSTED_PROXIES=$proxy_list

# Backup
# Changing these defaults is not recommended
BACKUP_DIR=/etc/bak/smbstack
# =============================================================================
ENV
    if ! chown root:www-data "$smbstack_env"; then
        abort "cannot set smbstack.env owner and group -abort"
    fi
    if ! chmod 640 "$smbstack_env"; then
        abort "cannot set smbstack.env permissions -abort"
    fi

    install_project_logrotate || abort "cannot configure smbstack log rotation -abort"

    register_project_cron "$share_dir" || abort "cannot write smbstack cron -abort"

    echo ""
    echo "Audit log : /var/log/samba/log.audit"
    echo "Web panel : http://localhost:3092/"
    echo "Shared web : http://localhost:3092/shared"
    echo "Audit web : http://localhost:3092/audit"
    echo "Report web : http://localhost:3092/report"
    echo "Shared dir : $share_dir"
    echo "Tools dir : $smbstack_tools"
    echo "Env file : $smbstack_env"
    echo "Check conf : testparm"
    echo ""
    echo "NOTE: shared folder is independent of Samba installer"
    echo "To remove it, you must do so manually: rm -rf $share_dir"
    echo "To use a custom path, edit smb.conf and smbweb.conf manually after install"
}

# ------------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------------

do_update() {
    [ -f "$smbstack_env" ] || abort "smbstack is not installed -abort"
    load_smbstack_env "$smbstack_env" "$env_keys" || abort "cannot read smbstack.env -abort"
    update_reset /etc/cron.d/smbstack
    local file mode
    for file in smbapi.php smbreport.html icon.svg smbaudit.html smbshared.php index.php smbaudit-diagnostic.php sw.js manifest.json; do
        update_file "$web_dir/$file" "$smbstack_web/$file" 755 www-data:www-data
    done
    for file in smbload.sh smbbk.sh smbreport.sh smbwatch.sh smbstackenv.sh; do
        mode=755
        [ "$file" != smbstackenv.sh ] || mode=644
        update_file "$tools_dir/$file" "$smbstack_tools/$file" "$mode" root:root
    done
    update_target "$smbstack_www/.size_cache" d700 www-data:www-data
    update_target /var/log/smbstack.log 640 root:adm
    update_target /etc/logrotate.d/smbstack
    update_target "$update_cron_file"
    update_target "${update_cron_file}.lock" 600
    update_preflight
    update_backup "$smbstack_tools/smbbk.sh"
    update_begin
    update_stop_daemon "$smbstack_tools/smbwatch.sh"
    update_stop_service apache2
    update_wait_jobs
    update_apply
    local deploy_file escaped_user
    escaped_user=$(printf '%s' "$LOCAL_USER" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
    for deploy_file in smbapi.php smbaudit.html smbaudit-diagnostic.php smbshared.php; do
        sed -i "s|your_user|$escaped_user|g; s|compartida|$SHARED_NAME|g" "$smbstack_web/$deploy_file" \
            || update_error "cannot configure file: $smbstack_web/$deploy_file"
    done
    install_project_logrotate || update_error "cannot configure smbstack log rotation"
    register_project_cron "$SHARED_PATH" || update_error "cannot regenerate smbstack cron"
    update_finish
    info "smbstack updated"
}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

do_uninstall() {
    if [ -x "$smbstack_tools/smbbk.sh" ]; then
        if "$smbstack_tools/smbbk.sh"; then
            info "backup taken with smbbk.sh"
        else
            abort "smbbk.sh: backup failed -abort"
        fi
    else
        abort "smbbk.sh: missing or not executable -abort"
    fi

    # load samba username and shared path from env
    uninstall_shared_path=""
    if [ -f "$smbstack_env" ]; then
        load_smbstack_env "$smbstack_env" "$env_keys"
        if [ -n "${SMBNAME:-}" ]; then
            pdbedit -x "$SMBNAME" 2>/dev/null \
                || warn "cannot remove Samba user $SMBNAME -alert"
        fi
        uninstall_shared_path="${SHARED_PATH:-}"
    fi
    userdel smbguest 2>/dev/null || true

    # apache sites
    a2dissite -q smbweb.conf &>/dev/null
    # Removes the <SERVER_IP>:3092 + 127.0.0.1:3092 pair install added.
    # Anchored to the fixed port 3092, which is unique to this project,
    # not to a specific IP.
    sed -i '/^Listen .*:3092$/d' /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/smbweb.conf
    # Not restored from ports.conf.bak on purpose: the lines above already
    # remove exactly the lines the installer added, without touching
    # anything else the admin may have added to ports.conf since install.
    rm -f /etc/apache2/ports.conf.bak

    # stop smbwatch and drop its cron entry and keys before removing its files
    [ -x "$smbstack_tools/smbwatch.sh" ] && "$smbstack_tools/smbwatch.sh" --uninstall 2>/dev/null || true

    # smbbk.sh cron entry
    [ -x "$smbstack_tools/smbbk.sh" ] && "$smbstack_tools/smbbk.sh" --uninstall || true

    # smbreport.sh cron entry
    [ -x "$smbstack_tools/smbreport.sh" ] && "$smbstack_tools/smbreport.sh" --uninstall || true

    # project web directory
    rm -rf "$smbstack_www"

    # administrative tree: tools, veto list and install config
    rm -rf "$smbstack_etc"

    # rsyslog
    rm -f /etc/rsyslog.d/fullaudit.conf
    [ -f /etc/rsyslog.conf.bak ] && cp -f /etc/rsyslog.conf.bak /etc/rsyslog.conf

    # logrotate
    [ -f /etc/logrotate.d/samba.bak ] && cp -f /etc/logrotate.d/samba.bak /etc/logrotate.d/samba
    [ -f /etc/logrotate.d/rsyslog.bak ] && cp -f /etc/logrotate.d/rsyslog.bak /etc/logrotate.d/rsyslog
    rm -f /etc/logrotate.d/smbstack && info "Removed /etc/logrotate.d/smbstack"
    rm -f /etc/logrotate.d/smbwatch && info "Removed /etc/logrotate.d/smbwatch"

    # smb.conf
    [ -f /etc/samba/smb.conf.bak ] && cp -f /etc/samba/smb.conf.bak /etc/samba/smb.conf

    # smbd.service
    [ -f /lib/systemd/system/smbd.service.bak ] && cp -f /lib/systemd/system/smbd.service.bak /lib/systemd/system/smbd.service

    # cron entries
    rm -f /etc/cron.d/smbstack /etc/cron.d/smbstack.update-disabled

    # samba packages
    DEBIAN_FRONTEND=noninteractive apt-get remove -y samba samba-common samba-common-bin smbclient winbind cifs-utils
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    systemctl daemon-reload
    systemctl restart apache2 rsyslog || abort "cannot restart apache2 or rsyslog -abort"

}

# ------------------------------------------------------------------------------
# STATUS
# ------------------------------------------------------------------------------

do_status() {
    echo "=== Samba Services ==="
    for service_name in smbd winbind; do
        if systemctl is-active --quiet "$service_name"; then
            echo "$service_name: RUNNING"
        else
            echo "$service_name: STOPPED"
        fi
    done

    echo ""
    echo "=== Apache Ports ==="
    for probe_port in 3092; do
        if ss -tlnp | grep -qE ":${probe_port}[[:space:]]"; then
            echo ":$probe_port OPEN"
        else
            echo ":$probe_port CLOSED"
        fi
    done

    echo ""
    echo "=== Audit Log ==="
    if [ -f /var/log/samba/log.audit ]; then
        echo "Last 5 entries:"
        tail -5 /var/log/samba/log.audit | sed 's/^/ /'
    else
        echo "/var/log/samba/log.audit not found"
    fi

    echo ""
    echo "=== smb.conf ==="
    if command -v testparm >/dev/null 2>&1; then
        testparm -s 2>/dev/null | head -20 | sed 's/^/ /'
    else
        echo " testparm not available"
    fi
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# Interactive menu shown when the script runs without arguments
show_menu() {
    while true; do
        echo ""
        echo "smbstack installer"
        echo "------------------"
        echo "1) Install"
        echo "2) Update"
        echo "3) Uninstall"
        echo "4) Status"
        echo "5) Exit"
        echo ""
        read -p "Select option [5]: " menu_option
        menu_option="${menu_option:-5}"
        case "$menu_option" in
            1) do_install; break ;;
            2) do_update || exit 1; break ;;
            3) do_uninstall; break ;;
            4) do_status; break ;;
            5) break ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# LOAD_CONF
# Load the shared configuration reader
source "$tools_dir/smbstackenv.sh"
env_keys='LOCAL_USER SHARED_NAME SHARED_PATH SMB_NET SMB_IFACE SMBNAME'

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Run the action given on the command line, or fall back to the menu
log "EVENT: smbsetup start..."

case "${1:-}" in
    --install) do_install ;;
    --update) do_update || exit 1 ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        err "invalid option -abort"
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac

log "EVENT: smbsetup done"
