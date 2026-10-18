#!/bin/bash
# maravento.com
#
################################################################################
#
# smbsetup -- installer for smbstack
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
    err "no local user; create one with sudo access -abort"
fi
info "using local user: $local_user"

# dependencies
for dep_pkg in apache2-utils libapache2-mod-php php logrotate acl openssl cron iproute2 sudo systemd util-linux zip inotify-tools procps coreutils findutils sed grep; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
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
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

source "$tools_dir/smbstackenv.sh"
env_keys='LOCAL_USER SHARED_NAME SHARED_PATH SMB_NET SMB_IFACE SMBNAME'

# CRON_D
# Add or replace one line in the project's single cron.d file
cron_d_set() {
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/smbstack"
    local cron_tmp

    cron_tmp=$(mktemp) || return 1
    if [ -f "$cron_file" ]; then
        grep -vF "$match" "$cron_file" > "$cron_tmp" || {
            [ "$?" -eq 1 ] || { rm -f "$cron_tmp"; return 1; }
        }
    fi
    if [ -n "$line" ]; then
        printf '%s\n' "$line" >> "$cron_tmp" || {
            rm -f "$cron_tmp"
            return 1
        }
    fi
    if [ -s "$cron_tmp" ]; then
        if ! install -m 644 -o root -g root "$cron_tmp" "$cron_file"; then
            rm -f "$cron_tmp"
            return 1
        fi
    else
        rm -f "$cron_file"
    fi
    rm -f "$cron_tmp"
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
    if [ -n "$(ss -lnH "-${proto,,}" "sport = :$port" 2>/dev/null)" ]; then
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
    cp -f "$conf_dir/smbweb.conf" /etc/apache2/sites-available/smbweb.conf
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
        # SMBSTACK_IFACE lets a caller (e.g. another installer) supply the
        # interface it already knows, instead of answering the prompt.
        if [ -n "${SMBSTACK_IFACE:-}" ]; then
            ip link show "$SMBSTACK_IFACE" &>/dev/null || abort "SMBSTACK_IFACE='$SMBSTACK_IFACE' not found on this system -abort"
            iface_answer="$SMBSTACK_IFACE"
            echo "Network interface: $iface_answer (preset)"
        else
            local default_iface
            default_iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1)
            echo "Available interfaces:"
            ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | sed 's/^/ /'
            while true; do
                read -p "Enter network interface [$default_iface]: " iface_answer
                iface_answer="${iface_answer:-$default_iface}"
                if [ -z "$iface_answer" ]; then
                    info "interface cannot be empty -retry"
                elif ! ip link show "$iface_answer" &>/dev/null; then
                    info "interface $iface_answer not found -retry"
                    iface_answer=""
                else
                    break
                fi
            done
        fi

        # Samba network -- derived from the interface, not asked: its address
        # and prefix already define the network authorised to use Samba and
        # the web panel.
        local iface_cidr iface_only iface_prefix o1 o2 o3 o4 ip_num mask_num net_num
        iface_cidr=$(ip -o -4 addr show dev "$iface_answer" scope global | awk '{print $4; exit}')
        [[ "$iface_cidr" =~ $UH_CIDR ]] || abort "cannot detect IPv4 address for interface $iface_answer -abort"
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

    # veto list required by the include line in smb.conf
    mkdir -p "$smbstack_acl"
    cp -f "$acl_dir/commonveto.txt" "$smbstack_acl/commonveto.txt"
    chmod 644 "$smbstack_acl/commonveto.txt"
    chown root:root "$smbstack_acl/commonveto.txt"

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

    # cron: recycle bin weekly cleanup
    cron_d_set "$share_dir/.recycle/" "@weekly root find \"$share_dir/.recycle/\" -depth -mindepth 1 -mtime +6 -delete >/dev/null 2>&1" || abort "cannot write smbstack cron -abort"

    # cron: folder size cache cleanup -- entries expire after SIZE_CACHE_TTL,
    # so anything older than an hour is dead weight
    cron_d_set "/var/www/smbstack/.size_cache" "@daily root find /var/www/smbstack/.size_cache -name \"*.cache\" -mmin +60 -delete >/dev/null 2>&1" || abort "cannot write smbstack cron -abort"

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
    # cron: service watchdog
    cron_d_set "$smbstack_tools/smbload.sh" "*/5 * * * * root $smbstack_tools/smbload.sh" || abort "cannot write smbstack cron -abort"

    systemctl daemon-reload

    # detect server IP from SMB_IFACE
    detected_ip=$(ip -4 addr show "$iface_answer" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
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
    mkdir -p "$smbstack_etc"
    cat > "$smbstack_env" <<ENV
# =============================================================================
# SMBstack
# /etc/smbstack/smbstack.env
# =============================================================================
LOCAL_USER=$local_user
SHARED_NAME=$folder_answer
SHARED_PATH=$share_dir
SMB_NET=$net_answer
SMB_IFACE=$iface_answer
SERVER_IP=$detected_ip
SMBNAME=$samba_account

# MAX_LOG_LINES: max lines read from the current (non-rotated) audit log
# file per request, by both smbapi.php and smbaudit-diagnostic.php.
# NOTE: smbaudit.html's own fetch request uses a fixed limit of 50000 in
# its JS code, independent of this value -- raising MAX_LOG_LINES here does
# not change what the audit viewer UI requests.
MAX_LOG_LINES=50000
# Report defaults
# Changing these defaults is not recommended
SMBREPORT_TOP_ROWS=30
SMBREPORT_TOP_FILES=50

# TRUSTED_PROXIES: IPv4 address(es), comma-separated, whose REMOTE_ADDR
# is trusted to supply the real client IP via CF-Connecting-IP /
# X-Forwarded-For headers (used by web/smbshared.php for audit logging).
# Default 127.0.0.1 avoids logging the loopback connection of a local
# tunnel (if any) as the client. Safe to leave as-is for LAN-only use.
TRUSTED_PROXIES=$proxy_list
# =============================================================================
ENV
    if ! chown root:www-data "$smbstack_env"; then
        abort "cannot set smbstack.env owner and group -abort"
    fi
    if ! chmod 640 "$smbstack_env"; then
        abort "cannot set smbstack.env permissions -abort"
    fi

    if [ -x "$smbstack_tools/smbbk.sh" ]; then
        "$smbstack_tools/smbbk.sh" --install || warn "smbbk.sh: monthly task setup failed -alert"
    fi

    if [ -x "$smbstack_tools/smbreport.sh" ]; then
        "$smbstack_tools/smbreport.sh" --install || warn "smbreport.sh: daily task setup failed -alert"
    fi

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
    local update_failed=0
    local -a update_failures=()
    local update_failure

    if [ ! -f "$smbstack_env" ]; then
        abort "smbstack is not installed -abort"
    fi

    # load saved config
    load_smbstack_env "$smbstack_env" "$env_keys"
    info "user=$LOCAL_USER shared=$SHARED_PATH"
    info "net=$SMB_NET iface=$SMB_IFACE"

    if [ -x "$smbstack_tools/smbbk.sh" ]; then
        if "$smbstack_tools/smbbk.sh"; then
            info "backup taken with smbbk.sh"
        else
            warn "smbbk.sh: backup failed -alert"
        fi
    else
        warn "smbbk.sh: missing or not executable -alert"
    fi

    # every file in web/ is application code and is always (re)deployed, which
    # also heals installs from before a file was added. The Apache vhost is not
    # here: it lives in sites-available, do_install wrote the network and the
    # paths into it, and a copy would undo that.
    for source_file in "$web_dir"/*; do
        [ -f "$source_file" ] || continue
        base_name="$(basename "$source_file")"
        dest_path="$smbstack_web/$base_name"
        if ! cp -f "$source_file" "$dest_path"; then
            warn "cannot update $base_name -alert"
            update_failed=1
            update_failures+=("cannot update $base_name")
            continue
        fi
        escaped_user=$(printf '%s' "$LOCAL_USER" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
        if sed -i "s|your_user|$escaped_user|g" "$dest_path" \
            && sed -i "s|compartida|$SHARED_NAME|g" "$dest_path"; then
            info "updated $base_name"
        else
            warn "cannot patch $base_name -alert"
            update_failed=1
            update_failures+=("cannot patch $base_name")
        fi
    done

    # tools
    mkdir -p "$smbstack_tools"
    if ! install -m 644 -o root -g root "$tools_dir/smbstackenv.sh" \
        "$smbstack_tools/smbstackenv.sh"; then
        warn "cannot update smbstackenv.sh -alert"
        update_failed=1
        update_failures+=("cannot update smbstackenv.sh")
    fi
    for tool_file in "$tools_dir"/*.sh; do
        [ -f "$tool_file" ] || continue
        [ "$(basename "$tool_file")" = smbstackenv.sh ] && continue
        base_name="$(basename "$tool_file")"
        if cp -f "$tool_file" "$smbstack_tools/$base_name" \
            && chmod +x "$smbstack_tools/$base_name"; then
            info "updated $base_name"
        else
            warn "cannot update $base_name -alert"
            update_failed=1
            update_failures+=("cannot update $base_name")
        fi
    done

    mkdir -p "$smbstack_www/.size_cache"
    if ! chown www-data:www-data "$smbstack_www/.size_cache"; then
        warn "cannot set owner and group on .size_cache -alert"
        update_failed=1
        update_failures+=("cannot set owner and group on .size_cache")
    fi
    if ! chmod 700 "$smbstack_www/.size_cache"; then
        warn "cannot set permissions on .size_cache -alert"
        update_failed=1
        update_failures+=("cannot set permissions on .size_cache")
    fi

    local cron_failed=0
    # cron: rewrite the project's own entries, so an install from an earlier
    # version picks up any change to a schedule or a command
    cron_d_set "$SHARED_PATH/.recycle/" "@weekly root find \"$SHARED_PATH/.recycle/\" -depth -mindepth 1 -mtime +6 -delete >/dev/null 2>&1" || cron_failed=1
    cron_d_set "/var/www/smbstack/.size_cache" "@daily root find /var/www/smbstack/.size_cache -name \"*.cache\" -mmin +60 -delete >/dev/null 2>&1" || cron_failed=1
    cron_d_set "$smbstack_tools/smbload.sh" "*/5 * * * * root $smbstack_tools/smbload.sh" || cron_failed=1

    # these two own their own schedule, so each one writes its own line
    for cron_tool in smbbk.sh smbreport.sh; do
        if [ -x "$smbstack_tools/$cron_tool" ]; then
            "$smbstack_tools/$cron_tool" --install || warn "$cron_tool: scheduled task setup failed -alert"
        fi
    done
    if [ "$cron_failed" -eq 0 ]; then
        info "updated cron entries"
    else
        warn "cannot update smbstack cron -alert"
        update_failed=1
        update_failures+=("cannot update smbstack cron")
    fi

    systemctl daemon-reload
    if ! systemctl restart smbd winbind rsyslog apache2; then
        warn "restart smbd winbind rsyslog apache2 failed -alert"
        update_failed=1
        update_failures+=("restart smbd winbind rsyslog apache2 failed")
    fi

    if [ "$update_failed" -ne 0 ]; then
        for update_failure in "${update_failures[@]}"; do
            err "$update_failure -abort"
        done
        return 1
    fi

}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

do_uninstall() {
    info "Run tools/smbbk.sh first if you want a backup"

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
    rm -f /etc/logrotate.d/smbwatch

    # smb.conf
    [ -f /etc/samba/smb.conf.bak ] && cp -f /etc/samba/smb.conf.bak /etc/samba/smb.conf

    # smbd.service
    [ -f /lib/systemd/system/smbd.service.bak ] && cp -f /lib/systemd/system/smbd.service.bak /lib/systemd/system/smbd.service

    # cron entries
    rm -f /etc/cron.d/smbstack

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
# MAIN
# ------------------------------------------------------------------------------

# MENU
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
            5) exit 0 ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

# ACTIONS
# Run the action given on the command line, or fall back to the menu
log "smbsetup start..."

case "${1:-}" in
    --install) do_install ;;
    --update) do_update || exit 1 ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac

log "smbsetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
