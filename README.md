# [SMBstack](https://github.com/maravento)

[![status-maintained](https://img.shields.io/badge/status-maintained-purple.svg)](https://github.com/maravento/smbstack)
[![last commit](https://img.shields.io/github/last-commit/maravento/smbstack)](https://github.com/maravento/smbstack)
[![Stargazers](https://img.shields.io/github/stars/maravento/smbstack?label=Stargazers)](https://github.com/maravento/smbstack/stargazers)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/maravento/smbstack)
[![Twitter Follow](https://img.shields.io/twitter/follow/maraventostudio.svg)](https://twitter.com/maraventostudio)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>SMBstack</b> is an open-source Samba stack installer for Debian-based systems. It deploys a shared folder with Recycle Bin, full audit logging via rsyslog, a web-based audit viewer, and a shared folder browser — all configured interactively through a single installer script.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>SMBstack</b> es un instalador de stack Samba de código abierto para sistemas basados en Debian. Despliega una carpeta compartida con Papelera de Reciclaje, auditoría completa vía rsyslog, un visor web de auditoría y un explorador web de la carpeta compartida — todo configurado de forma interactiva a través de un único script instalador.
    </td>
  </tr>
</table>

## Requirements

---

**⚠️ WARNING:** Only tested on Ubuntu 24.04 LTS. Other versions or distros not tested, use at your own risk.

- Apache2 and PHP
- rsyslog
- logrotate
- inotify-tools (required by `smbwatch.sh`)

```bash
apt-get install -y apache2 apache2-utils libapache2-mod-php
apt-get install -y --reinstall apache2-doc
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Important</strong>
      <ul>
        <li>nginx must not be running.</li>
        <li>SMBstack uses Apache2 exclusively on port 3092, because it is listed as <strong>Unassigned</strong> by IANA. For more information visit <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Importante</strong>
      <ul>
        <li>nginx no debe estar en ejecución.</li>
        <li>SMBstack usa Apache2 exclusivamente en el puerto 3092, ya que está listado como <strong>Sin asignar</strong> por IANA. Para más información visita <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
  </tr>
</table>

## Web Interface

---

### Main Menu

[![smbstack-main](https://raw.githubusercontent.com/maravento/smbstack/master/img/smbstack-main.png)](https://github.com/maravento/smbstack)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      There are two ways to reach each view: <code>http://localhost:3092/?tab=audit</code> or <code>http://localhost:3092/audit</code> for the audit viewer, and <code>http://localhost:3092/?tab=shared</code> or <code>http://localhost:3092/shared</code> for the shared folder browser. Both forms are valid.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Hay dos maneras de llegar a cada vista: <code>http://localhost:3092/?tab=audit</code> o <code>http://localhost:3092/audit</code> para el visor de auditoría, y <code>http://localhost:3092/?tab=shared</code> o <code>http://localhost:3092/shared</code> para el explorador de carpeta compartida. Ambas formas son válidas.
    </td>
  </tr>
</table>

### SMBaudit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The audit viewer (<code>http://localhost:3092/?tab=audit</code>) displays Samba activity logs in real time. It allows filtering by date range, IP and action, free-text search, pagination, and export to PDF.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El visor de auditoría (<code>http://localhost:3092/?tab=audit</code>) muestra los logs de actividad de Samba en tiempo real. Permite filtrar por rango de fechas, IP y acción, búsqueda de texto libre, paginación, y exportación a PDF.
    </td>
  </tr>
</table>

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Records are paginated (50/100/200/500 per page) with page navigation, so large audit logs stay responsive.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Los registros están paginados (50/100/200/500 por página) con navegación entre páginas, para que los logs de auditoría extensos se mantengan ágiles.
    </td>
  </tr>
</table>

[![smbstack-botton](https://raw.githubusercontent.com/maravento/smbstack/master/img/smbstack-botton.png)](https://github.com/maravento/smbstack)

### SMBshared

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The shared folder browser (<code>http://localhost:3092/</code>) provides a unified interface with two tabs: <strong>Shared</strong> and <strong>Audit</strong>. The Shared tab allows navigating the shared folder structure, opening or downloading documents, and moving items to the recycle bin. Root-level folders are protected — items cannot be uploaded, created, or deleted from the root level.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El explorador de carpeta compartida (<code>http://localhost:3092/</code>) ofrece una interfaz unificada con dos pestañas: <strong>Shared</strong> y <strong>Audit</strong>. La pestaña Shared permite navegar la estructura de carpetas, abrir o descargar documentos y mover elementos a la papelera de reciclaje. Las carpetas de primer nivel están protegidas — no se pueden subir archivos, crear carpetas ni eliminar elementos desde la raíz.
    </td>
  </tr>
</table>

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Both views support a light/dark theme toggle from the top bar, synced across tabs.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Ambas vistas admiten un interruptor de tema claro/oscuro desde la barra superior, sincronizado entre pestañas.
    </td>
  </tr>
</table>

[![smbstack-views](https://raw.githubusercontent.com/maravento/smbstack/master/img/smbstack-views.png)](https://github.com/maravento/smbstack)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Inside any subfolder, the toolbar allows uploading single or multiple files simultaneously, creating new folders, and reloading the view. All operations are recorded in the audit log with the client's IP address.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Dentro de cualquier subcarpeta, la barra de herramientas permite subir uno o varios archivos simultáneamente, crear nuevas carpetas y recargar la vista. Todas las operaciones quedan registradas en el log de auditoría con la IP del cliente.
    </td>
  </tr>
</table>

[![smbstack-files](https://raw.githubusercontent.com/maravento/smbstack/master/img/smbstack-files.png)](https://github.com/maravento/smbstack)

## Scope

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>What SMBstack does:</b>
      <ul>
        <li>Installs and configures Samba with a shared folder, Recycle Bin and group permissions</li>
        <li>Configures full audit logging via rsyslog to <code>/var/log/samba/log.audit</code></li>
        <li>Deploys a web-based audit log viewer at <code>http://localhost:3092/?tab=audit</code></li>
        <li>Deploys a web-based shared folder browser at <code>http://localhost:3092/?tab=shared</code></li>
        <li>Configures logrotate for all Samba logs</li>
        <li>Installs a service watchdog (<code>smbload.sh</code>) via cron <code>@reboot</code></li>
        <li>Installs a shared folder size monitor (<code>smbwatch.sh</code>) — self-managed, independent of the installer</li>
        <li>Saves installation config to <code>/var/www/smbstack/smbstack.env</code> for future updates</li>
        <li>NetBIOS disabled by default (enable manually if needed, see <a href="#netbios">NetBIOS</a> section)</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Lo que SMBstack hace:</b>
      <ul>
        <li>Instala y configura Samba con carpeta compartida, Papelera de Reciclaje y permisos de grupo</li>
        <li>Configura auditoría completa vía rsyslog en <code>/var/log/samba/log.audit</code></li>
        <li>Despliega un visor web de auditoría en <code>http://localhost:3092/?tab=audit</code></li>
        <li>Despliega un explorador web de la carpeta compartida en <code>http://localhost:3092/?tab=shared</code></li>
        <li>Configura logrotate para todos los logs de Samba</li>
        <li>Instala un watchdog de servicios (<code>smbload.sh</code>) vía cron <code>@reboot</code></li>
        <li>Instala un monitor de espacio de la carpeta compartida (<code>smbwatch.sh</code>) — autogestionado, independiente del instalador</li>
        <li>Guarda la configuración de instalación en <code>/var/www/smbstack/smbstack.env</code> para futuras actualizaciones</li>
        <li>NetBIOS deshabilitado por defecto (actívalo manualmente si lo necesitas, ver sección <a href="#netbios">NetBIOS</a>)</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>Out of scope (not implemented):</b>
      <ul>
        <li>Active Directory / domain controller</li>
        <li>Multiple shared folders</li>
        <li>Custom paths outside <code>/home/$local_user/</code> (must be edited manually)</li>
        <li>IPv6</li>
        <li>LDAP</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Fuera de alcance (no implementado):</b>
      <ul>
        <li>Active Directory / controlador de dominio</li>
        <li>Múltiples carpetas compartidas</li>
        <li>Rutas personalizadas fuera de <code>/home/$local_user/</code> (debe editarse manualmente)</li>
        <li>IPv6</li>
        <li>LDAP</li>
      </ul>
    </td>
  </tr>
</table>

## Repository Structure

---

```
smbstack/
├── smbinstall.sh               # Installer: install, update, uninstall, status
├── README.md
├── conf/                       # Configuration files deployed to system paths
│   ├── smb.conf                # Samba main config (placeholders: your_user, compartida)
│   └── fullaudit.conf          # rsyslog full audit rule
├── img/
│   ├── smbstack-main.png
│   ├── smbstack-files.png
│   ├── smbstack-botton.png
│   └── smbstack-views.png
├── web/                        # Web files deployed to /var/www/smbstack/web/
│   ├── smbweb.conf             # Apache vhost (:3092/?tab=audit and :3092/?tab=shared)
│   ├── index.php               # Main page (Audit / Shared tabs)
│   ├── smbaudit.html           # Audit log viewer UI
│   ├── smbapi.php              # Audit log reader API
│   ├── smbaudit-diagnostic.php # Audit log diagnostic tool
│   └── shared.php              # Shared folder dynamic browser
└── tools/                      # Scripts deployed to /var/www/smbstack/tools/
    ├── smbload.sh              # Service watchdog (smbd + winbind)
    └── smbwatch.sh             # Shared folder size monitor (self-managed)
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Files and directories generated at runtime (not included in the repository):
    </td>
    <td style="width: 50%; vertical-align: top;">
      Archivos y directorios generados en runtime (no incluidos en el repositorio):
    </td>
  </tr>
</table>

```
/var/www/smbstack/
└── smbstack.env                # Saved install config (user, paths, network, trusted proxies, watch limit, max log lines)

/var/log/smbwatch.log           # smbwatch.sh runtime log

/home/$local_user/shared/       # Shared folder (independent of the installer)
├── .recycle/                   # Recycle Bin (smbguest/, www-data/, smbwatch/)
└── DEMO/                       # Demo folder

/etc/logrotate.d/samba          # Generated by installer (heredoc)
/var/log/samba/log.audit        # Created by rsyslog
/var/log/samba/log.samba        # Created by installer, written directly by smbd
```

## HOW TO USE

---

### Install

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Download the repository and run the installer:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Descarga el repositorio y ejecuta el instalador:
    </td>
  </tr>
</table>

```bash
git clone --depth=1 https://github.com/maravento/smbstack.git
cd smbstack
sudo bash smbinstall.sh
```

The installer will prompt for:

| Prompt | Description |
|--------|-------------|
| Shared folder name | Name for the shared folder (created under `/home/$local_user/`) |
| Samba server network | IP/network in CIDR format (e.g. `192.168.1.0/24`) |
| Network interface | Selected from available interfaces listed |
| Samba username | Samba account to create |
| Overwrite smb.conf | Only asked if `/etc/samba/smb.conf` already exists |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>$local_user</code> is the local Linux user detected automatically by the installer: among users within the system's normal UID range (<code>UID_MIN</code>-<code>UID_MAX</code> from <code>/etc/login.defs</code>, excluding <code>/false</code>/<code>/nologin</code> shells) who belong to the <code>sudo</code> group, the one with the lowest UID is selected. It becomes the owner of the shared folder and the base name for the Samba account.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>$local_user</code> es el usuario local de Linux detectado automáticamente por el instalador: entre los usuarios dentro del rango normal de UID (<code>UID_MIN</code>-<code>UID_MAX</code> de <code>/etc/login.defs</code>, excluyendo shells <code>/false</code>/<code>/nologin</code>) que pertenezcan al grupo <code>sudo</code>, se selecciona el de menor UID. Se convierte en el propietario de la carpeta compartida y el nombre base de la cuenta Samba.
    </td>
  </tr>
</table>

### Update & Uninstall

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To update or uninstall SMBstack, download the updated repository, enter the folder and run:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para actualizar o desinstalar SMBstack, descarga el repositorio actualizado, entra a la carpeta y ejecuta:
    </td>
  </tr>
</table>

```bash
cd smbstack
sudo bash smbinstall.sh --update
# or | o
sudo bash smbinstall.sh --uninstall
```

| File | `--update` | `--uninstall` |
|------|-----------|---------------|
| `conf/smb.conf` | ⛔ not touched (user-customized) | ✅ restored from `.bak` |
| `conf/fullaudit.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/smbweb.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/index.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit.html` | ✅ overwritten | ✅ removed |
| `web/smbapi.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit-diagnostic.php` | ✅ overwritten | ✅ removed |
| `web/shared.php` | ✅ overwritten | ✅ removed |
| `tools/smbload.sh` | ✅ overwritten | ✅ removed |
| `tools/smbwatch.sh` | ✅ overwritten | ✅ removed |
| `/var/www/smbstack/smbstack.env` | ⛔ preserved | ✅ removed |
| Shared folder (`/home/$local_user/shared/`) | ⛔ never touched | ⛔ never touched |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>--update</code> only refreshes application code (web PHP/HTML viewers and <code>tools/*.sh</code>). Configuration files deployed at install time (<code>smb.conf</code>, <code>fullaudit.conf</code>, <code>smbweb.conf</code>) are never overwritten by <code>--update</code>, since they may contain manual edits (custom shares, <code>hosts allow</code>, interfaces, etc.). To pick up changes to these files after an update, compare them manually against <code>conf/</code> and <code>web/smbweb.conf</code> in the repository and apply changes by hand.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>--update</code> solo actualiza el código de la aplicación (visores web PHP/HTML y <code>tools/*.sh</code>). Los archivos de configuración desplegados en la instalación (<code>smb.conf</code>, <code>fullaudit.conf</code>, <code>smbweb.conf</code>) nunca son sobreescritos por <code>--update</code>, ya que pueden contener ediciones manuales (shares personalizados, <code>hosts allow</code>, interfaces, etc.). Para incorporar cambios en estos archivos tras una actualización, compáralos manualmente contra <code>conf/</code> y <code>web/smbweb.conf</code> en el repositorio y aplica los cambios a mano.
    </td>
  </tr>
</table>

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The shared folder is independent of the installer. To remove it, do so manually: <code>rm -rf /home/$local_user/shared</code>
    </td>
    <td style="width: 50%; vertical-align: top;">
      La carpeta compartida es independiente del instalador. Para eliminarla, hazlo manualmente: <code>rm -rf /home/$local_user/shared</code>
    </td>
  </tr>
</table>

### Status

```bash
sudo bash smbinstall.sh --status
```

Shows: smbd and winbind service status, Apache port 3092, last 5 audit log entries, and `testparm` summary.

### Config

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      After installation, the main configuration files are:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Tras la instalación, los archivos de configuración principales son:
    </td>
  </tr>
</table>

| Description | File |
|-------------|------|
| Samba main config | `/etc/samba/smb.conf` |
| Audit rsyslog rule | `/etc/rsyslog.d/fullaudit.conf` |
| Web vhost (audit + shared) | `/etc/apache2/sites-available/smbweb.conf` |
| Log rotation | `/etc/logrotate.d/samba` |
| Install config | `/var/www/smbstack/smbstack.env` |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbstack.env</code> sets <code>TRUSTED_PROXIES="127.0.0.1"</code> by default. It tells <code>web/shared.php</code> to use the <code>CF-Connecting-IP</code> / <code>X-Forwarded-For</code> header (if present) instead of <code>REMOTE_ADDR</code> when logging the client IP for requests arriving from localhost — so a local tunnel's loopback connection isn't recorded as the "client" in the audit log. No effect on direct LAN access.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbstack.env</code> establece <code>TRUSTED_PROXIES="127.0.0.1"</code> por defecto. Le indica a <code>web/shared.php</code> que use el encabezado <code>CF-Connecting-IP</code> / <code>X-Forwarded-For</code> (si está presente) en lugar de <code>REMOTE_ADDR</code> al registrar la IP del cliente para solicitudes que lleguen desde localhost — así la conexión loopback de un túnel local no se registra como el "cliente" en el log de auditoría. Sin efecto en acceso LAN directo.
    </td>
  </tr>
</table>

```bash
# Verify Samba config | Verificar configuración de Samba
testparm

# Restart services | Reiniciar servicios
sudo systemctl restart smbd winbind

# View audit log | Ver log de auditoría
tail -f /var/log/samba/log.audit

# List Samba users | Listar usuarios de Samba
sudo pdbedit -L
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To use a custom shared folder path outside <code>/home/$local_user/</code>, edit <code>/etc/samba/smb.conf</code> and <code>/etc/apache2/sites-available/smbweb.conf</code> manually after installation.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para usar una ruta de carpeta compartida personalizada fuera de <code>/home/$local_user/</code>, edita <code>/etc/samba/smb.conf</code> y <code>/etc/apache2/sites-available/smbweb.conf</code> manualmente tras la instalación.
    </td>
  </tr>
</table>

### Recycle Bin

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack uses the Samba <code>vfs_recycle</code> module to redirect file deletions to a hidden recycle bin instead of permanently removing them. The bin is stored inside the shared folder under <code>.recycle/</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack usa el módulo <code>vfs_recycle</code> de Samba para redirigir las eliminaciones a una papelera de reciclaje oculta en lugar de borrar permanentemente los archivos. La papelera se almacena dentro de la carpeta compartida en <code>.recycle/</code>.
    </td>
  </tr>
</table>

#### Recycle bin channels

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack writes to the recycle bin through three independent channels, each operating under a different system context:
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack escribe en la papelera de reciclaje a través de tres canales independientes, cada uno operando bajo un contexto de sistema diferente:
    </td>
  </tr>
</table>

| Channel | System user | Recycle path |
|---------|-------------|--------------|
| SMB (LAN clients) | `smbguest` (set by `force user` in `smb.conf`) | `.recycle/smbguest/` |
| Web interface (Apache) | `www-data` | `.recycle/www-data/` |
| Size-limit watchdog (`tools/smbwatch.sh`) | `${LOCAL_USER:-root}:sambashare` | `.recycle/smbwatch/` |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This is why the recycle bin directory contains one subdirectory per channel:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Por eso el directorio de la papelera contiene un subdirectorio por canal:
    </td>
  </tr>
</table>

```
.recycle/
├── smbguest/               # Files deleted by Windows/Linux SMB clients on the LAN
│   └── DOCUMENTS/
│       ├── report.docx
│       └── Copy #1 of report.docx
├── www-data/               # Files deleted via the web browser interface
│   └── 20260623/
│       └── invoice.pdf
└── smbwatch/               # Files auto-moved by the size-limit watchdog
    └── 20260711/
        └── bigfile.iso
```

#### File versioning

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      When <code>recycle:versions = yes</code> is active, deleting a file that already exists in the recycle bin does not overwrite it — the new copy is saved alongside the original with a <code>Copy #N of</code> prefix:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Cuando <code>recycle:versions = yes</code> está activo, eliminar un archivo que ya existe en la papelera no lo sobreescribe — la nueva copia se guarda junto a la original con el prefijo <code>Copy #N of</code>:
    </td>
  </tr>
</table>

```
.recycle/smbguest/DOCUMENTS/
├── report.docx             ← first deletion
└── Copy #1 of report.docx  ← second deletion of the same file
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To exclude specific file types from versioning, use <code>recycle:noversions</code>. These types are still recycled, but repeated deletions <strong>overwrite</strong> the previous copy in the bin rather than creating a numbered duplicate:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para excluir tipos de archivo del versionado, usa <code>recycle:noversions</code>. Estos archivos siguen yendo a la papelera, pero eliminaciones repetidas <strong>sobreescriben</strong> la copia anterior en lugar de crear una nueva numerada:
    </td>
  </tr>
</table>

```ini
# All files keep multiple versions:
recycle:versions = yes

# These types are recycled but NOT versioned — second delete overwrites the first:
recycle:noversions = *.dat,*.ini
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Use <code>noversions</code> for files where accumulating copies adds no value: runtime data files, config dumps, ini snapshots, and similar.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Usa <code>noversions</code> para archivos donde acumular copias no aporta valor: archivos de datos en tiempo de ejecución, volcados de configuración, snapshots de ini y similares.
    </td>
  </tr>
</table>

#### Configuration reference

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `recycle:repository` | `.recycle/%U` | SMB channel recycle bin, resolves to `smbguest` / Papelera del canal SMB, resuelve a `smbguest` |
| `recycle:directory_mode` | `0775` | Group-writable recycle directory / Directorio escribible por el grupo |
| `recycle:keeptree` | `yes` | Preserve original folder structure / Preservar estructura de carpetas |
| `recycle:versions` | `yes` | Keep multiple versions of deleted files / Mantener múltiples versiones |
| `recycle:noversions` | `*.dat,*.ini` | Exclude patterns from versioning / Excluir patrones del versionado |
| `recycle:touch` | `yes` | Update access time when recycled / Actualizar tiempo de acceso al reciclar |
| `recycle:exclude` | `*.tmp,*.temp,*.o,~$*,*.~??,*.log,*.trace,*.TMP,*.asv` | Permanently delete matching files / Eliminar permanentemente archivos que coincidan |
| `recycle:exclude_dir` | `/temp,/tmp,/cache,/.Trash-1000` | Bypass recycle bin for directories / Omitir papelera para directorios |
| `recycle:maxsize` | `1073741824` | Max file size (1 GB) / Tamaño máximo (1 GB) |
| `hide files` | `/.recycle/` | Hide recycle directory from clients / Ocultar papelera a los clientes |

#### Automatic cleanup

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer registers a weekly cron job (under <code>root</code>) that removes recycled files older than 7 days:
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador registra una tarea cron semanal (bajo <code>root</code>) que elimina los archivos reciclados con más de 7 días de antigüedad:
    </td>
  </tr>
</table>

```bash
@weekly find "/home/$local_user/shared/.recycle/" -depth -mindepth 1 -mtime +7 -delete
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To adjust the retention period or inspect the entry:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para ajustar el período de retención o inspeccionar la entrada:
    </td>
  </tr>
</table>

```bash
sudo crontab -e
```

---

### Full Audit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack uses the Samba <code>vfs_full_audit</code> module to log file operations to <code>/var/log/samba/log.audit</code> via rsyslog. Only successful operations are recorded; failures are suppressed to keep the log clean.
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack usa el módulo <code>vfs_full_audit</code> de Samba para registrar operaciones de archivos en <code>/var/log/samba/log.audit</code> vía rsyslog. Solo se registran operaciones exitosas; los fallos se suprimen para mantener el log limpio.
    </td>
  </tr>
</table>

#### Configuration reference

| Parameter | Value | Description | Descripción |
|-----------|-------|-------------|-------------|
| `full_audit:logfile` | `/var/log/samba/log.audit` | Destination log file, written via the rsyslog rule in `/etc/rsyslog.d/fullaudit.conf`. | Archivo de log de destino, escrito mediante la regla rsyslog en `/etc/rsyslog.d/fullaudit.conf`. |
| `full_audit:prefix` | `%I\|%m\|%S` | Fields prepended to each log entry: `%I` = client IP address, `%m` = client machine name, `%S` = share name. | Campos que se anteponen a cada entrada del log: `%I` = IP del cliente, `%m` = nombre del equipo cliente, `%S` = nombre del share. |
| `full_audit:success` | `mkdirat renameat unlinkat pwrite` | VFS operations logged when they succeed. See table below. | Operaciones VFS que se registran cuando tienen éxito. Ver tabla a continuación. |
| `full_audit:failure` | `none` | No failed operations are logged. | No se registran operaciones fallidas. |
| `full_audit:facility` | `LOCAL5` | rsyslog facility used to route audit entries to the dedicated log file, keeping them separate from general system logs. | Facility de rsyslog usada para enrutar las entradas de auditoría al archivo dedicado, manteniéndolas separadas de los logs generales del sistema. |
| `full_audit:priority` | `notice` | Syslog priority level assigned to audit entries. | Nivel de prioridad syslog asignado a las entradas de auditoría. |

#### Logged operations

| Samba syscall | Triggered by | Desencadenado por |
|---------------|--------------|-------------------|
| `mkdirat` | Creating a directory via SMB or the web interface | Creación de un directorio vía SMB o la interfaz web |
| `renameat` | Renaming or moving a file or folder. Also triggered by Windows clients when saving a file (temp file + rename pattern). | Renombrado o movimiento de archivo o carpeta. También lo disparan los clientes Windows al guardar un archivo (patrón de archivo temporal + renombrado). |
| `unlinkat` | File deletion — permanent or moved to the recycle bin. See caveat below. | Borrado de archivo — permanente o movido a la papelera. Ver matiz abajo. |
| `pwrite` | Data written to an open file, via SMB or via the web interface. See caveat below. | Datos escritos en un archivo abierto, vía SMB o vía la interfaz web. Ver matiz abajo. |

##### Caveats

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li><b><code>renameat</code> log format:</b> logged as <code>source_path|destination_path</code>. Does not appear for recycle bin operations.</li>
        <li><b>Recycled vs. permanently deleted:</b> <code>unlinkat</code> cannot tell them apart — <code>vfs_full_audit</code> intercepts the call before <code>vfs_recycle</code> redirects it. Check the <code>.recycle/</code> directory on disk to know which happened.</li>
        <li><b><code>pwrite</code> source:</b> logged both by Samba (SMB clients) and by <code>shared.php</code> (web uploads, which never go through <code>smbd</code>). To tell them apart, check the syslog <code>$user</code> field before <code>smbd_audit:</code> — the web interface always logs as <code>www-data</code>.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li><b>Formato de log de <code>renameat</code>:</b> se registra como <code>ruta_origen|ruta_destino</code>. No aparece para operaciones de papelera de reciclaje.</li>
        <li><b>Reciclado vs. eliminado permanente:</b> <code>unlinkat</code> no puede distinguirlos — <code>vfs_full_audit</code> intercepta la llamada antes de que <code>vfs_recycle</code> la redirija. Revisa el directorio <code>.recycle/</code> en el sistema de archivos para saber cuál ocurrió.</li>
        <li><b>Origen de <code>pwrite</code>:</b> lo registran tanto Samba (clientes SMB) como <code>shared.php</code> (subidas web, que nunca pasan por <code>smbd</code>). Para distinguirlas, revisa el campo <code>$user</code> del syslog antes de <code>smbd_audit:</code> — la interfaz web siempre lo registra como <code>www-data</code>.</li>
      </ul>
    </td>
  </tr>
</table>

##### Why `openat` is not audited

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Evaluated and deliberately left out of <code>full_audit:success</code> by default. Every file/directory open — including plain browsing, reads and downloads, not just writes — generates an entry, so a single Explorer window left open on a busy folder produces dozens of near-duplicate lines per second. That noise buries the events actually worth reviewing without adding meaningful traceability, since <code>pwrite</code> already covers the write itself.
      <br><br>
      This is a project default, not a hard limitation. To audit opens/reads too, add it yourself in <code>/etc/samba/smb.conf</code>:
      <pre><code>full_audit:success = mkdirat renameat unlinkat pwrite openat</code></pre>
      Then run <code>testparm</code> and <code>systemctl restart smbd</code>. <code>--update</code> won't touch this — <code>smb.conf</code> is never overwritten after install, so the change persists.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Se evaluó y se dejó fuera de <code>full_audit:success</code> por defecto, a propósito. Cada apertura de archivo o carpeta — incluyendo simple navegación, lecturas y descargas, no solo escrituras — genera una entrada, así que una sola ventana del Explorador abierta sobre una carpeta con actividad produce decenas de líneas casi idénticas por segundo. Ese ruido entierra los eventos que sí vale la pena revisar sin aportar trazabilidad real, ya que <code>pwrite</code> ya cubre la escritura en sí.
      <br><br>
      Esto es un valor por defecto del proyecto, no una limitación forzosa. Para auditar también aperturas/lecturas, agrégalo tú mismo en <code>/etc/samba/smb.conf</code>:
      <pre><code>full_audit:success = mkdirat renameat unlinkat pwrite openat</code></pre>
      Luego ejecuta <code>testparm</code> y <code>systemctl restart smbd</code>. <code>--update</code> no lo tocará — <code>smb.conf</code> nunca se sobreescribe tras la instalación, así que el cambio persiste.
    </td>
  </tr>
</table>

---

### smbload

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbload.sh</code> is a service watchdog that ensures <code>smbd</code> and <code>winbind</code> are running at boot. It is automatically registered in cron <code>@reboot</code> during installation and runs from <code>/var/www/smbstack/tools/</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbload.sh</code> es un watchdog de servicios que garantiza que <code>smbd</code> y <code>winbind</code> estén en ejecución al arrancar. Se registra automáticamente en cron <code>@reboot</code> durante la instalación y corre desde <code>/var/www/smbstack/tools/</code>.
    </td>
  </tr>
</table>

```bash
# sudo crontab -l
@reboot /var/www/smbstack/tools/smbload.sh
```

### smbwatch

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbwatch.sh</code> monitors first-level subdirectories of the shared folder in real time using <code>inotifywait</code>. When a subdirectory exceeds the configured size limit, the triggering file is automatically moved to <code>.recycle/smbwatch/&lt;YYYYMMDD&gt;/</code> — its own channel, separate from <code>.recycle/smbguest/</code> and <code>.recycle/www-data/</code> (see <a href="#recycle-bin-channels">Recycle bin channels</a>). It is self-managed and independent of the installer — it reads its configuration from <code>smbstack.env</code> and prompts for any missing values.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbwatch.sh</code> monitorea en tiempo real las subcarpetas de primer nivel de la carpeta compartida usando <code>inotifywait</code>. Cuando una subcarpeta supera el límite de tamaño configurado, el archivo que disparó el evento se mueve automáticamente a <code>.recycle/smbwatch/&lt;YYYYMMDD&gt;/</code> — su propio canal, separado de <code>.recycle/smbguest/</code> y <code>.recycle/www-data/</code> (ver <a href="#recycle-bin-channels">Recycle bin channels</a>). Es autogestionado e independiente del instalador — lee su configuración desde <code>smbstack.env</code> y solicita los valores faltantes.
    </td>
  </tr>
</table>

```bash
# Start
sudo /var/www/smbstack/tools/smbwatch.sh start

# Stop
sudo /var/www/smbstack/tools/smbwatch.sh stop

# Status
sudo /var/www/smbstack/tools/smbwatch.sh status
```

### NetBIOS

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      NetBIOS is a legacy protocol with documented security limitations, including unauthenticated name resolution and susceptibility to spoofing/poisoning attacks (e.g., NBT-NS and LLMNR poisoning). Consequently, it is disabled by default (<code>disable netbios = yes</code> in <code>smb.conf</code>), and the installer does not provide an option to enable it. Environments requiring compatibility with legacy Windows clients must enable NetBIOS manually after installation.
    </td>
    <td style="width: 50%; vertical-align: top;">
      NetBIOS es un protocolo legado con limitaciones de seguridad ampliamente documentadas, entre ellas la resolución de nombres sin autenticación y la susceptibilidad a ataques de suplantación o envenenamiento (por ejemplo, NBT-NS y LLMNR poisoning). En consecuencia, permanece deshabilitado de forma predeterminada (<code>disable netbios = yes</code> en <code>smb.conf</code>) y el instalador no ofrece una opción para habilitarlo. Los entornos que requieran compatibilidad con clientes Windows legados deberán habilitar NetBIOS manualmente después de la instalación.
    </td>
  </tr>
</table>

```bash
# Enable NetBIOS in smb.conf
sudo sed -i 's/^\s*disable netbios\s*=.*/   disable netbios = no/' /etc/samba/smb.conf
sudo sed -i "s/^;\s*netbios name\s*=.*/   netbios name = YOUR_HOSTNAME/" /etc/samba/smb.conf

# Start nmbd
sudo systemctl enable --now nmbd.service
sudo systemctl restart smbd

# Open the required ports (adjust IFACE to your Samba interface)
sudo iptables -A INPUT   -i IFACE -p udp -m multiport --dports 137,138 -j ACCEPT
sudo iptables -A FORWARD -i IFACE -p udp -m multiport --dports 137,138 -j ACCEPT
sudo iptables -A INPUT   -i IFACE -p tcp --dport 139 -j ACCEPT
sudo iptables -A FORWARD -i IFACE -p tcp --dport 139 -j ACCEPT

# Optional: rotate nmbd's log
sudo tee -a /etc/logrotate.d/samba > /dev/null <<'EOF'
/var/log/samba/log.nmbd {
    weekly
    missingok
    rotate 7
    postrotate
        systemctl reload nmbd 2>/dev/null || true
    endscript
    compress
    notifempty
}
EOF
```

## ⚠️ WARNING: Network Access

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This project is designed to run locally and be accessed over a LAN. It is not recommended to expose it to the internet, as it lacks the hardening required for public-facing deployments.
      If you choose to publish it despite this warning, it is strongly recommended to do so through an on-demand tunnel rather than opening ports directly. This approach lets you start and stop public access at will, without permanently exposing your server.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este proyecto está diseñado para ejecutarse localmente y ser accedido en red LAN. No se recomienda exponerlo a internet, ya que no cuenta con el endurecimiento necesario para despliegues públicos.
      Si decide publicarlo a pesar de esta advertencia, se recomienda hacerlo a través de un túnel bajo demanda en lugar de abrir puertos directamente. Este enfoque le permite iniciar y detener el acceso público a voluntad, sin exponer el servidor de forma permanente.
    </td>
  </tr>
</table>

> **CSRF protection:** `web/shared.php` has no login by design — guest access for the whole LAN (and the tunnel, if enabled) is intentional. What it does have is a per-session token on the four state-changing forms (upload, new folder, new file, recycle), so a POST is only accepted if it was actually loaded from the page first. This blocks a malicious site elsewhere from silently auto-submitting a form to your server through a visitor's browser (CSRF); it does **not** restrict who can use the browser itself — that's still governed purely by network reachability (LAN / tunnel), same as today.
>
> **Protección CSRF:** `web/shared.php` no tiene login por diseño — el acceso de invitado para toda la LAN (y el túnel, si está activo) es intencional. Lo que sí tiene es un token por sesión en los cuatro formularios que modifican estado (subir, nueva carpeta, nuevo archivo, papelera), de modo que un POST solo se acepta si realmente se cargó la página antes. Esto bloquea que un sitio malicioso ajeno autoenvíe un formulario a tu servidor a través del navegador de un visitante (CSRF); **no** restringe quién puede usar el explorador en sí — eso sigue gobernado únicamente por el alcance de red (LAN / túnel), igual que hoy.

**Optional tunnel:**
- [Cloudflare Tunnel with Zero Trust Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)

## NOTICE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>This repository</strong>
      <ul>
        <li>May include third-party components.</li>
        <li>Does not accept Pull Requests. Changes must be proposed via Issues.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Este repositorio</strong>
      <ul>
        <li>Puede incluir componentes de terceros.</li>
        <li>No acepta Pull Requests. Los cambios deben proponerse mediante Issues.</li>
      </ul>
    </td>
  </tr>
</table>

## SPONSOR THIS PROJECT

---

[![Image](https://raw.githubusercontent.com/maravento/winexternal/master/img/maravento-paypal.png)](https://paypal.me/maravento)

## PROJECT LICENSES

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This project uses a dual-licensing model to balance software freedom with content protection:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este proyecto utiliza un modelo de licencia dual para equilibrar la libertad del software con la protección del contenido:
    </td>
  </tr>
</table>

| Content | Licensed Under |
|---|---|
|Scripts, Binaries, Infrastructure|[![GPL-3.0](https://img.shields.io/badge/Open_Core-GPLv3-blue.svg?style=for-the-badge&labelWidth=120&logoWidth=20)](https://www.gnu.org/licenses/gpl.txt)|
|RAG, Workers, Specialized Modules, Docs|[![CC](https://img.shields.io/badge/Core_Engine-CC_BY--NC--ND_4.0-lightgrey.svg?style=for-the-badge&labelWidth=120&logoWidth=20)](https://creativecommons.org/licenses/by-nc-nd/4.0/)|

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
