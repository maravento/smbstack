#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Samba with Shared Folder, Recycle Bin and Audit
# https://github.com/maravento/smbstack
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

# dependencies
for dep_pkg in apache2 apache2-utils libapache2-mod-php php rsyslog logrotate acl openssl cron iproute2 sudo systemd util-linux; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        echo "ERROR: dependency '$dep_pkg' is not installed -- abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
conf_dir="$script_dir/conf"
web_dir="$script_dir/web"
tools_dir="$script_dir/tools"
acl_dir="$script_dir/acl"
smbstack_www="/var/www/smbstack"
smbstack_web="$smbstack_www/web"
smbstack_tools="$smbstack_www/tools"
smbstack_env="$smbstack_www/smbstack.env"

# validation -- one variable per thing validated; use directly with =~
UH_OCT='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'
UH_NETMASK='^(0\.0\.0\.0|128\.0\.0\.0|192\.0\.0\.0|224\.0\.0\.0|240\.0\.0\.0|248\.0\.0\.0|252\.0\.0\.0|254\.0\.0\.0|255\.0\.0\.0|255\.128\.0\.0|255\.192\.0\.0|255\.224\.0\.0|255\.240\.0\.0|255\.248\.0\.0|255\.252\.0\.0|255\.254\.0\.0|255\.255\.0\.0|255\.255\.128\.0|255\.255\.192\.0|255\.255\.224\.0|255\.255\.240\.0|255\.255\.248\.0|255\.255\.252\.0|255\.255\.254\.0|255\.255\.255\.0|255\.255\.255\.128|255\.255\.255\.192|255\.255\.255\.224|255\.255\.255\.240|255\.255\.255\.248|255\.255\.255\.252|255\.255\.255\.254|255\.255\.255\.255)$'
UH_DNS='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(,(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9]))*$'
UH_UINT='^(0|[1-9][0-9]*)$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
UH_MAC_RE='([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'
UH_MAC="^${UH_MAC_RE}$"
UH_PREFIX='0.0.0.0:0 128.0.0.0:1 192.0.0.0:2 224.0.0.0:3 240.0.0.0:4 248.0.0.0:5 252.0.0.0:6 254.0.0.0:7 255.0.0.0:8 255.128.0.0:9 255.192.0.0:10 255.224.0.0:11 255.240.0.0:12 255.248.0.0:13 255.252.0.0:14 255.254.0.0:15 255.255.0.0:16 255.255.128.0:17 255.255.192.0:18 255.255.224.0:19 255.255.240.0:20 255.255.248.0:21 255.255.252.0:22 255.255.254.0:23 255.255.255.0:24 255.255.255.128:25 255.255.255.192:26 255.255.255.224:27 255.255.255.240:28 255.255.255.248:29 255.255.255.252:30 255.255.255.254:31 255.255.255.255:32'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: command failed after $max_attempts attempts: $*"
            exit 1
        fi
        echo "WARNING: command failed (attempt $attempt/$max_attempts), retrying in 10s: $*"
        attempt=$((attempt + 1))
        sleep 10
    done
}

check_repo() {
    local missing_dir=0
    for repo_subdir in "$conf_dir" "$web_dir" "$tools_dir" "$acl_dir"; do
        if [ ! -d "$repo_subdir" ] || [ -z "$(ls -A "$repo_subdir" 2>/dev/null)" ]; then
            missing_dir=1
            break
        fi
    done
    if [ "$missing_dir" -eq 1 ]; then
        echo ""
        echo "ERROR: Repository files not found. Run:"
        echo ""
        echo "git clone https://github.com/maravento/smbstack"
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
            echo "ERROR: Folder name can only contain letters, numbers, hyphens and underscores"
            folder_answer=""
        else
            break
        fi
    done
    share_dir="/home/$local_user/$folder_answer"

    if [ -d "$share_dir" ]; then
        echo "Folder '$share_dir' already exists. Verifying permissions..."
        perms_ok=1

        actual_owner=$(stat -c "%U" "$share_dir")
        actual_group=$(stat -c "%G" "$share_dir")
        actual_mode=$(stat -c "%a" "$share_dir")

        if [ "$actual_owner" != "$local_user" ] || [ "$actual_group" != "sambashare" ]; then
            echo "Owner/group mismatch (got $actual_owner:$actual_group, expected $local_user:sambashare). Fixing..."
            chown "$local_user":sambashare "$share_dir"
            perms_ok=0
        fi

        if [ "$actual_mode" != "755" ]; then
            echo "Mode mismatch (got $actual_mode, expected 755). Fixing..."
            chmod 755 "$share_dir"
            perms_ok=0
        fi

        while IFS= read -r shared_subdir; do
            dir_owner=$(stat -c "%U" "$shared_subdir")
            dir_group=$(stat -c "%G" "$shared_subdir")
            dir_mode=$(stat -c "%a" "$shared_subdir")
            if [ "$dir_owner" != "$local_user" ] || [ "$dir_group" != "sambashare" ]; then
                echo "Fixing owner/group on: $shared_subdir"
                chown "$local_user":sambashare "$shared_subdir"
                perms_ok=0
            fi
            if [ "$dir_mode" != "2775" ]; then
                echo "Fixing mode on: $shared_subdir"
                chmod 2775 "$shared_subdir"
                perms_ok=0
            fi
        done < <(find "$share_dir" -mindepth 1 -path "$share_dir/.recycle" -prune -o -type d -print)

        while IFS= read -r shared_file; do
            file_owner=$(stat -c "%U" "$shared_file")
            file_group=$(stat -c "%G" "$shared_file")
            file_mode=$(stat -c "%a" "$shared_file")
            if [ "$file_owner" != "$local_user" ] || [ "$file_group" != "sambashare" ]; then
                echo "Fixing owner/group on: $shared_file"
                chown "$local_user":sambashare "$shared_file"
                perms_ok=0
            fi
            if [ "$file_mode" != "664" ]; then
                echo "Fixing mode on: $shared_file"
                chmod 664 "$shared_file"
                perms_ok=0
            fi
        done < <(find "$share_dir" -mindepth 1 -path "$share_dir/.recycle" -prune -o -type f -print)

        if ! getfacl "$share_dir" 2>/dev/null | grep -q "user:www-data:r-x"; then
            echo "Missing ACL for www-data. Fixing..."
            setfacl -m u:www-data:r-x "$share_dir"
            perms_ok=0
        fi
        # root ACL: mask r-x (blocks group write on root), default mask rwx (allows group write in subdirs)
        setfacl -m mask::r-x "$share_dir"
        setfacl -d -m g:sambashare:rwx "$share_dir"
        setfacl -d -m mask::rwx "$share_dir"
        # recycle bin
        mkdir -p "$share_dir/.recycle"
        chown www-data:www-data "$share_dir/.recycle"
        chmod 755 "$share_dir/.recycle"
        setfacl -m g:sambashare:rwx "$share_dir/.recycle"
        setfacl -d -m g:sambashare:rwx "$share_dir/.recycle"

        if [ "$perms_ok" -eq 1 ]; then
            echo "Permissions OK"
        else
            echo "Permissions corrected"
        fi
    else
        sudo -u "$local_user" mkdir -p "$share_dir"
        chmod 755 "$share_dir"
        chown "$local_user":sambashare "$share_dir"
        sudo -u "$local_user" mkdir -p "$share_dir/DEMO"
        sudo -u "$local_user" bash -c "echo 'this is a demo file' > '$share_dir/DEMO/demo.txt'"
        find "$share_dir" -mindepth 1 -type d -exec chown "$local_user":sambashare {} \; -exec chmod 2775 {} \;
        find "$share_dir" -mindepth 1 -type f -exec chown "$local_user":sambashare {} \; -exec chmod 664 {} \;
        setfacl -m u:www-data:r-x "$share_dir"
        setfacl -m mask::r-x "$share_dir"
        setfacl -d -m g:sambashare:rwx "$share_dir"
        setfacl -d -m mask::rwx "$share_dir"
        # recycle bin
        mkdir -p "$share_dir/.recycle"
        chown www-data:www-data "$share_dir/.recycle"
        chmod 755 "$share_dir/.recycle"
        setfacl -m g:sambashare:rwx "$share_dir/.recycle"
        setfacl -d -m g:sambashare:rwx "$share_dir/.recycle"
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
        [ -f "$smbstack_env" ] && existing_share=$(grep "^SHARED_NAME=" "$smbstack_env" | cut -d= -f2 | tr -d '"')
        if [ -n "$existing_share" ] && grep -q "\[${existing_share}\]" /etc/samba/smb.conf 2>/dev/null; then
            already_installed=1
            skip_reasons+=" - smb.conf already configured: /etc/samba/smb.conf\n"
        fi
    fi

    if [ "$already_installed" -eq 1 ]; then
        echo ""
        echo "ERROR: Samba is already installed. Aborting."
        echo ""
        printf "%b" "$skip_reasons"
        echo ""
        echo "To update, run: sudo bash smbinstall.sh --update"
        echo ""
        exit 1
    fi
}

do_install() {
    check_already_installed

    # dependency check
    if systemctl is-active --quiet nginx; then
        echo "ERROR: nginx is running. Disable it first: systemctl stop nginx"
        exit 1
    fi

    if ! systemctl is-active --quiet apache2; then
        echo "ERROR: apache2 is not running. Start it first: systemctl start apache2"
        exit 1
    fi

    if ! systemctl is-active --quiet rsyslog; then
        echo "ERROR: rsyslog is not running. Start it first: systemctl start rsyslog"
        exit 1
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
        echo "smbguest created"
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
    cp -f "$web_dir/index.php" "$smbstack_web/"
    cp -f "$web_dir/smbaudit.html" "$smbstack_web/"
    cp -f "$web_dir/smbapi.php" "$smbstack_web/"
    cp -f "$web_dir/smbaudit-diagnostic.php" "$smbstack_web/"
    cp -f "$web_dir/shared.php" "$smbstack_web/"
    cp -f "$web_dir/manifest.json" "$smbstack_web/"
    cp -f "$web_dir/sw.js" "$smbstack_web/"
    cp -f "$web_dir/icon.svg" "$smbstack_web/"
    chmod -R 755 "$smbstack_web"
    chown -R www-data:www-data "$smbstack_web"

    # apache vhosts (both in smbweb.conf)
    # Listen is opened on all interfaces here only because SERVER_IP isn't
    # known yet at this point (SMB_IFACE hasn't been prompted for). It gets
    # narrowed down to just the LAN IP + loopback further below, once
    # SERVER_IP is detected.
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    # drop any :3092 Listen line(s) left by a previous/partial install run
    # before re-adding 0.0.0.0, so reruns don't produce duplicate Listen
    # directives (which makes apache2 fail to start on restart).
    sed -i '/^Listen .*:3092$/d' /etc/apache2/ports.conf
    echo "Listen 0.0.0.0:3092" | tee -a /etc/apache2/ports.conf
    cp -f "$web_dir/smbweb.conf" /etc/apache2/sites-available/smbweb.conf
    a2ensite -q smbweb.conf

    # replace placeholders in deployed files (not in repo)
    for deploy_file in \
        /etc/apache2/sites-available/smbweb.conf \
        "$smbstack_web/smbaudit.html" \
        "$smbstack_web/smbapi.php" \
        "$smbstack_web/smbaudit-diagnostic.php" \
        "$smbstack_web/shared.php"; do
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
    cp -f /etc/logrotate.d/smbwatch{,.bak} &>/dev/null
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
        while true; do
            read -p "Enter Samba server IP/network [192.168.0.0/24]: " net_answer
            net_answer="${net_answer:-192.168.0.0/24}"
            if ! [[ "$net_answer" =~ $UH_CIDR ]]; then
                echo "ERROR: Invalid format. Expected x.x.x.x/xx (e.g. 192.168.0.0/24)"
                net_answer=""
            else
                break
            fi
        done
        local default_iface
        default_iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1)
        echo "Available interfaces:"
        ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | sed 's/^/ /'
        while true; do
            read -p "Enter network interface [$default_iface]: " iface_answer
            iface_answer="${iface_answer:-$default_iface}"
            if [ -z "$iface_answer" ]; then
                echo "ERROR: Interface cannot be empty"
            elif ! ip link show "$iface_answer" &>/dev/null; then
                echo "ERROR: Interface $iface_answer not found"
                iface_answer=""
            else
                break
            fi
        done
    }

    apply_smb_conf_placeholders() {
        local escaped_user
        escaped_user=$(printf '%s' "$local_user" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" /etc/samba/smb.conf
        sed -i "s|compartida|$folder_answer|g" /etc/samba/smb.conf
    }

    apply_smb_conf_interfaces() {
        sed -i "s|interfaces = .*|interfaces = 127.0.0.0/8 $net_answer $iface_answer|" /etc/samba/smb.conf
        sed -i "s|hosts allow = .*|hosts allow = 127.0.0.1, $net_answer|" /etc/samba/smb.conf
        echo "interfaces set to: 127.0.0.0/8 $net_answer $iface_answer"
        echo "hosts allow set to: 127.0.0.1, $net_answer"
    }

    if [ -f /etc/samba/smb.conf ]; then
        while true; do
            read -p "smb.conf already exists. Overwrite? (y/n) [n]: " overwrite_answer
            overwrite_answer="${overwrite_answer:-n}"
            case "$overwrite_answer" in
                [Yy])
                    cp -f /etc/samba/smb.conf{,.bak}
                    echo "Backup saved: /etc/samba/smb.conf.bak"
                    cp -f "$conf_dir/smb.conf" /etc/samba/smb.conf
                    apply_smb_conf_placeholders
                    prompt_smb_net_iface
                    apply_smb_conf_interfaces
                    break
                    ;;
                [Nn])
                    echo "Skipping smb.conf"
                    echo "WARNING: existing smb.conf kept as-is. The [compartida] share and the"
                    echo "full_audit/recycle VFS were NOT applied. Add them manually or"
                    echo "re-run and choose 'y' to deploy the bundled smb.conf."
                    prompt_smb_net_iface
                    break
                    ;;
                *)
                    echo "ERROR: Answer y or n"
                    ;;
            esac
        done
    else
        cp -f "$conf_dir/smb.conf" /etc/samba/smb.conf
        apply_smb_conf_placeholders
        prompt_smb_net_iface
        apply_smb_conf_interfaces
    fi

    # veto list (static, optional -- see the commented "include" line in smb.conf)
    mkdir -p /etc/samba/acl
    cp -f "$acl_dir/commonveto.txt" /etc/samba/acl/commonveto.txt
    chmod 644 /etc/samba/acl/commonveto.txt
    chown root:root /etc/samba/acl/commonveto.txt

    # rsyslog
    cp -f /etc/rsyslog.conf{,.bak} &>/dev/null
    sed -i -E 's/^(\s*(\$FileOwner|\$FileGroup|\$FileCreateMode|\$DirCreateMode|\$Umask|\$PrivDropToUser|\$PrivDropToGroup)\b.*)/#\1/' /etc/rsyslog.conf
    cp -f "$conf_dir/fullaudit.conf" /etc/rsyslog.d/fullaudit.conf
    chmod 644 /etc/rsyslog.d/fullaudit.conf
    chown root:root /etc/rsyslog.d/fullaudit.conf
    usermod -a -G adm www-data

    cp -f /etc/logrotate.d/rsyslog{,.bak} &>/dev/null
    grep -qF 'create 0644 syslog adm' /etc/logrotate.d/rsyslog || \
        sed -i '/sharedscripts/a \ create 0644 syslog adm' /etc/logrotate.d/rsyslog
    grep -qF 'su syslog adm' /etc/logrotate.d/rsyslog || \
        sed -i '/^{$/a \	su syslog adm' /etc/logrotate.d/rsyslog

    logrotate_out=$(logrotate -f /etc/logrotate.d/samba 2>&1)
    if echo "$logrotate_out" | grep -qi "error"; then
        echo "WARNING: logrotate error"
        echo "$logrotate_out"
    fi

    # cron: recycle bin weekly cleanup
    crontab -l 2>/dev/null > "/var/www/smbstack/crontab-$(date +%Y%m%d%H%M%S).bak" || true
    if ! crontab -l 2>/dev/null | grep -qF ".recycle"; then
        (crontab -l 2>/dev/null || true; echo "@weekly find \"$share_dir/.recycle/\" -depth -mindepth 1 -mtime +7 -delete >/dev/null 2>&1") | crontab -
    fi

    # service watchdog
    mkdir -p "$smbstack_tools"
    cp -f "$tools_dir"/*.sh "$smbstack_tools/"
    chmod +x "$smbstack_tools"/*.sh
    # cron: service watchdog at reboot
    if ! crontab -l 2>/dev/null | grep -qF "smbload.sh"; then
        (crontab -l 2>/dev/null || true; echo "@reboot $smbstack_tools/smbload.sh") | crontab -
    fi

    systemctl daemon-reload
    systemctl restart smbd winbind rsyslog apache2

    # detect server IP from SMB_IFACE
    detected_ip=$(ip -4 addr show "$iface_answer" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if ! [[ "$detected_ip" =~ $UH_IPV4 ]]; then
        echo "WARNING: Could not detect IP for interface $iface_answer"
        echo "The web panel will keep listening on all interfaces (0.0.0.0:3092)."
        detected_ip=""
    else
        # Narrow the web panel's Listen directive from all-interfaces down to
        # just the chosen LAN IP, plus loopback (needed for a local tunnel
        # daemon like cloudflared, which connects to Apache via 127.0.0.1 --
        # see TRUSTED_PROXIES). This was written as 0.0.0.0:3092 earlier
        # because SERVER_IP wasn't known yet at that point in the install.
        sed -i "s|^Listen 0.0.0.0:3092\$|Listen $detected_ip:3092\nListen 127.0.0.1:3092|" /etc/apache2/ports.conf
        systemctl restart apache2
    fi

    # create Samba account for local user
    samba_account="$local_user"
    while true; do
        read -s -p "Enter Samba password for $samba_account: " smb_pass; echo
        if [ "${#smb_pass}" -lt 8 ]; then
            echo "Password must be at least 8 characters. Try again."
            continue
        fi
        read -s -p "Confirm password: " smb_pass2; echo
        [ "$smb_pass" = "$smb_pass2" ] && break
        echo "Passwords do not match. Try again."
    done
    printf "%s\n%s\n" "$smb_pass" "$smb_pass" | smbpasswd -a -s "$samba_account"
    unset smb_pass smb_pass2

    # TRUSTED_PROXIES: used by web/shared.php to decide whether the
    # CF-Connecting-IP / X-Forwarded-For headers can be trusted when
    # logging the client IP for web operations (upload/mkdir/delete).
    # Set to 127.0.0.1 so that, if this host is ever reached through a
    # local tunnel (cloudflared or similar), the tunnel's own loopback
    # connection isn't logged as the "client" - the real visitor IP from
    # the forwarded header is used instead. For plain LAN access this has
    # no effect: REMOTE_ADDR is simply used as-is.
    proxy_list="127.0.0.1"

    # save install config
    cat > "$smbstack_env" <<ENV
LOCAL_USER="$local_user"
SHARED_NAME="$folder_answer"
SHARED_PATH="$share_dir"
SMB_NET="$net_answer"
SMB_IFACE="$iface_answer"
SERVER_IP="$detected_ip"
SMBNAME="$samba_account"

# MAX_LOG_LINES: max lines read from the current (non-rotated) audit log
# file per request, by both smbapi.php and smbaudit-diagnostic.php.
# NOTE: smbaudit.html's own fetch request uses a fixed limit of 50000 in
# its JS code, independent of this value -- raising MAX_LOG_LINES here does
# not change what the audit viewer UI requests.
MAX_LOG_LINES="50000"

# TRUSTED_PROXIES: IPv4 address(es), comma-separated, whose REMOTE_ADDR
# is trusted to supply the real client IP via CF-Connecting-IP /
# X-Forwarded-For headers (used by web/shared.php for audit logging).
# Default 127.0.0.1 avoids logging the loopback connection of a local
# tunnel (if any) as the client. Safe to leave as-is for LAN-only use.
TRUSTED_PROXIES="$proxy_list"
ENV
    chown root:www-data "$smbstack_env"
    chmod 640 "$smbstack_env"

    echo ""
    echo "Audit log : /var/log/samba/log.audit"
    echo "Audit web : http://localhost:3092/audit"
    echo "Shared web : http://localhost:3092/shared"
    echo "Shared dir : $share_dir"
    echo "Tools dir : $smbstack_tools"
    echo "Env file : $smbstack_env"
    echo "Check conf : testparm"
    echo ""
    echo "NOTE: The shared folder is independent of the Samba installer."
    echo "To remove it, you must do so manually: rm -rf $share_dir"
    echo "To use a custom path, edit smb.conf and smbweb.conf manually after install."
    echo ""
    echo "DONE"
}

# ------------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------------

do_update() {
    if [ ! -f "$smbstack_env" ]; then
        echo "ERROR: smbstack is not installed."
        exit 1
    fi

    # load saved config
    local allowed_env_keys=" LOCAL_USER SHARED_NAME SHARED_PATH SMB_NET SMB_IFACE SERVER_IP SMBNAME TRUSTED_PROXIES WATCH_LIMIT_GB WATCH_EXCLUDE MAX_LOG_LINES "
    while IFS= read -r env_line; do
        [[ "$env_line" =~ ^[A-Z_]+=.* ]] && {
            env_key="${env_line%%=*}"
            env_value="${env_line#*=}"
            env_value=$(echo "$env_value" | tr -d '"')
            case "$allowed_env_keys" in
                *" $env_key "*) export "$env_key=$env_value" ;;
                *) echo "WARNING: ignoring unknown key in $smbstack_env: $env_key" ;;
            esac
        }
    done < "$smbstack_env"
    echo "Updating with config: user=$LOCAL_USER shared=$SHARED_PATH net=$SMB_NET iface=$SMB_IFACE"
    echo ""

    # index.php, manifest.json, sw.js, icon.svg: static, no placeholders,
    # always (re)deployed -- heals installs from before these files were
    # added to do_install's copy list
    for base_name in index.php manifest.json sw.js icon.svg; do
        if [ -f "$web_dir/$base_name" ]; then
            cp -f "$web_dir/$base_name" "$smbstack_web/$base_name"
            echo "Updated: $base_name"
        fi
    done

    # web files (application code only - no user-customized config files)
    for source_file in "$web_dir"/*; do
        [ -f "$source_file" ] || continue
        base_name="$(basename "$source_file")"
        case "$base_name" in
            smbaudit.html|smbapi.php|smbaudit-diagnostic.php|shared.php)
                dest_path="$smbstack_web/$base_name"
                ;;
            *)
                continue
                ;;
        esac
        [ -f "$dest_path" ] || continue
        mkdir -p "$smbstack_www/backups"
        cp -f "$dest_path" "$smbstack_www/backups/$base_name.bak" &>/dev/null
        cp -f "$source_file" "$dest_path"
        escaped_user=$(printf '%s' "$LOCAL_USER" | tr -d '\n' | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" "$dest_path"
        sed -i "s|compartida|$SHARED_NAME|g" "$dest_path"
        echo "Updated: $base_name"
    done

    # tools
    for tool_file in "$tools_dir"/*.sh; do
        [ -f "$tool_file" ] || continue
        base_name="$(basename "$tool_file")"
        cp -f "$smbstack_tools/$base_name" "$smbstack_tools/$base_name.bak" &>/dev/null
        cp -f "$tool_file" "$smbstack_tools/$base_name"
        chmod +x "$smbstack_tools/$base_name"
        echo "Updated: $base_name"
    done

    mkdir -p "$smbstack_www/.size_cache"
    chown www-data:www-data "$smbstack_www/.size_cache"
    chmod 700 "$smbstack_www/.size_cache"

    systemctl daemon-reload
    systemctl restart smbd winbind rsyslog apache2

    echo ""
    echo "DONE"
}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

do_uninstall() {
    # load samba username and shared path from env
    uninstall_shared_path=""
    if [ -f "$smbstack_env" ]; then
        SMBNAME=$(grep "^SMBNAME=" "$smbstack_env" | cut -d= -f2 | tr -d '"')
        if [ -n "$SMBNAME" ]; then
            pdbedit -x "$SMBNAME" 2>/dev/null || true
            echo "Samba user removed: $SMBNAME"
        fi
        uninstall_shared_path=$(grep "^SHARED_PATH=" "$smbstack_env" | cut -d= -f2- | tr -d '"')
    fi
    userdel smbguest 2>/dev/null || true

    # apache sites
    a2dissite -q smbweb.conf &>/dev/null
    # Matches whichever variant install left behind: the original
    # 0.0.0.0:3092 (if SERVER_IP detection failed), or the narrowed
    # <SERVER_IP>:3092 + 127.0.0.1:3092 pair. Anchored to the fixed port
    # 3092, which is unique to this project, not to a specific IP.
    sed -i '/^Listen .*:3092$/d' /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/smbweb.conf
    # Not restored from ports.conf.bak on purpose: the line above already
    # removes exactly the one line the installer added, without touching
    # anything else the admin may have added to ports.conf since install.
    rm -f /etc/apache2/ports.conf.bak

    # stop smbwatch before removing its files
    [ -x "$smbstack_tools/smbwatch.sh" ] && "$smbstack_tools/smbwatch.sh" stop 2>/dev/null || true

    # project web directory
    rm -rf "$smbstack_www"

    # rsyslog
    rm -f /etc/rsyslog.d/fullaudit.conf
    [ -f /etc/rsyslog.conf.bak ] && cp -f /etc/rsyslog.conf.bak /etc/rsyslog.conf

    # logrotate
    [ -f /etc/logrotate.d/samba.bak ] && cp -f /etc/logrotate.d/samba.bak /etc/logrotate.d/samba
    [ -f /etc/logrotate.d/rsyslog.bak ] && cp -f /etc/logrotate.d/rsyslog.bak /etc/logrotate.d/rsyslog
    rm -f /etc/logrotate.d/smbwatch /etc/logrotate.d/smbwatch.bak

    # smb.conf
    [ -f /etc/samba/smb.conf.bak ] && cp -f /etc/samba/smb.conf.bak /etc/samba/smb.conf

    # smbd.service
    [ -f /lib/systemd/system/smbd.service.bak ] && cp -f /lib/systemd/system/smbd.service.bak /lib/systemd/system/smbd.service

    # cron entries
    # Anchored to the exact lines smbinstall.sh adds (full command/path),
    # instead of bare substrings, so an unrelated user cron job that merely
    # mentions "smbload.sh" or ".recycle" isn't swept away too.
    crontab -l 2>/dev/null > "/root/crontab-uninstall-$(date +%Y%m%d%H%M%S).bak" || true
    cron_tmp=$(mktemp)
    crontab -l 2>/dev/null > "$cron_tmp" || true
    if [ -n "$uninstall_shared_path" ]; then
        grep -vF "find \"$uninstall_shared_path/.recycle/\"" "$cron_tmp" > "${cron_tmp}.next" || true
        mv "${cron_tmp}.next" "$cron_tmp"
    fi
    grep -vF "$smbstack_tools/smbload.sh" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    grep -vF "$smbstack_tools/smbwatch.sh" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    crontab "$cron_tmp"
    rm -f "$cron_tmp"

    # samba packages
    DEBIAN_FRONTEND=noninteractive apt-get remove -y samba samba-common samba-common-bin smbclient winbind cifs-utils
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    systemctl daemon-reload
    systemctl restart apache2 rsyslog

    echo "DONE"
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
    for check_port in 3092; do
        if ss -tlnp | grep -qE ":${check_port}[[:space:]]"; then
            echo ":$check_port OPEN"
        else
            echo ":$check_port CLOSED"
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
    testparm -s 2>/dev/null | head -20 | sed 's/^/ /' || echo " testparm not available"
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
            2) do_update; break ;;
            3) do_uninstall; break ;;
            4) do_status; break ;;
            5) exit 0 ;;
            *) echo "ERROR: Invalid option" ;;
        esac
    done
}

# ACTIONS
# Run the action given on the command line, or fall back to the menu
case "${1:-}" in
    --install) do_install ;;
    --update) do_update ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac
