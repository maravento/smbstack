# [SMBstack](https://github.com/maravento) — Samba Server Stack

[![status-maintained](https://img.shields.io/badge/status-maintained-purple.svg)](https://github.com/maravento/smbstack)
[![last commit](https://img.shields.io/github/last-commit/maravento/smbstack)](https://github.com/maravento/smbstack)
[![Stargazers](https://img.shields.io/github/stars/maravento/smbstack?label=Stargazers)](https://github.com/maravento/smbstack/stargazers)
[![Twitter Follow](https://img.shields.io/twitter/follow/maraventostudio.svg)](https://twitter.com/maraventostudio)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>Many small and medium-sized businesses need to share files on their local network. They may also need to recover deleted files, review access records, manage files through a browser and control storage usage. Dedicated NAS devices often provide these functions, but their cost can be a barrier in some environments.</p>
      <p>One alternative is to use <strong>Samba</strong> on Linux. A standard installation lets you share files and folders; additional components are needed for the other functions.</p>
      <p><strong>SMBstack</strong> provides part of this infrastructure using <strong>Samba</strong> on Ubuntu as its base.</p>
      <p><strong>Samba</strong> remains responsible for file sharing and permission management. <strong>SMBstack</strong> adds a recycle bin with separate channels for each source, audit logging through <code>rsyslog</code>, a web panel with three views and a daily disk usage report.</p>
      <p>In the background, <code>smbload</code> monitors the services, <code>smbwatch</code> enforces folder size limits and <code>smbbk</code> backs up the configuration.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Muchas pequeñas y medianas empresas necesitan compartir archivos en su red local. Además, pueden necesitar recuperar archivos eliminados, consultar los accesos, gestionar archivos desde un navegador y controlar el espacio utilizado. Estas funciones suelen ofrecerse en dispositivos NAS, cuyo costo puede ser una barrera en algunos entornos.</p>
      <p>Una alternativa es usar <strong>Samba</strong> en Linux. La instalación estándar permite compartir archivos y carpetas; para añadir las demás funciones se necesitan componentes adicionales.</p>
      <p><strong>SMBstack</strong> proporciona parte de esta infraestructura utilizando <strong>Samba</strong> sobre Ubuntu como base.</p>
      <p><strong>Samba</strong> sigue a cargo de compartir archivos y gestionar permisos. <strong>SMBstack</strong> añade una papelera con canales separados según el origen de los archivos, auditoría mediante <code>rsyslog</code>, un panel web con tres vistas y un informe diario de uso de disco.</p>
      <p>En segundo plano, <code>smbload</code> supervisa los servicios, <code>smbwatch</code> controla el tamaño de las carpetas y <code>smbbk</code> crea respaldos de la configuración.</p>
    </td>
  </tr>
</table>

## REQUIREMENTS

---

**⚠️ WARNING:** Tested on Ubuntu 24.04/26.04 LTS. Use on other versions or distributions is at your own risk.

- Apache2 and PHP (`apache2`, `apache2-utils`, `libapache2-mod-php`, `php`)
- `rsyslog`, `logrotate`
- `acl`, `openssl`, `cron`, `iproute2`, `sudo`, `systemd`, `util-linux`, `zip` (checked by `smbsetup.sh`)
- `inotify-tools`, `procps`, `coreutils`, `findutils`, `cron`, `util-linux`, `sed`, `grep` (checked by `tools/smbwatch.sh`)
- `procps`, `samba`, `winbind`, `util-linux`, `coreutils`, `sed`, `systemd` (checked by `tools/smbload.sh`)
- `zip`, `coreutils`, `util-linux`, `cron` (checked by `tools/smbbk.sh`)
- `findutils`, `coreutils`, `util-linux`, `cron` (checked by `tools/smbreport.sh`)

```bash
apt-get install -y apache2 apache2-utils libapache2-mod-php php rsyslog logrotate \
    acl openssl cron iproute2 sudo systemd util-linux sed grep inotify-tools \
    procps coreutils findutils zip
```

The Samba packages (`samba`, `samba-common`, `samba-common-bin`, `smbclient`, `winbind`, `cifs-utils`) are installed by `smbsetup.sh` itself.

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Important</strong>
      <ul>
        <li>The installer aborts if <code>nginx</code>, <code>lighttpd</code>, <code>caddy</code>, <code>ksmbd-tools</code> or <code>syslog-ng</code> are installed.</li>
        <li>The web panel listens on port <code>3092</code>, registered by <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">IANA</a> as Unassigned.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Importante</strong>
      <ul>
        <li>El instalador aborta si <code>nginx</code>, <code>lighttpd</code>, <code>caddy</code>, <code>ksmbd-tools</code> o <code>syslog-ng</code> están instalados.</li>
        <li>El panel web escucha en el puerto <code>3092</code>, registrado por <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">IANA</a> como Sin asignar.</li>
      </ul>
    </td>
  </tr>
</table>

## WEB INTERFACE

---

### Main Menu

[![smbstack-main](./img/smbstack-main.png)](https://github.com/maravento/smbstack)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>Each view can be opened in two ways:</p>
      <ul>
        <li><code>http://localhost:3092/?tab=shared</code>, <code>?tab=audit</code> or <code>?tab=report</code>: opens the panel on the corresponding tab and keeps the tab bar visible.</li>
        <li><code>http://localhost:3092/shared/</code>, <code>/audit/</code> or <code>/report/</code>: opens only the selected view, without the tab bar.</li>
      </ul>
      <p>Both forms of access are valid.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Cada vista puede abrirse de dos maneras:</p>
      <ul>
        <li><code>http://localhost:3092/?tab=shared</code>, <code>?tab=audit</code> o <code>?tab=report</code>: abre el panel en la pestaña correspondiente y mantiene visible la barra de pestañas.</li>
        <li><code>http://localhost:3092/shared/</code>, <code>/audit/</code> o <code>/report/</code>: abre únicamente la vista seleccionada, sin la barra de pestañas.</li>
      </ul>
      <p>Ambas formas de acceso son válidas.</p>
    </td>
  </tr>
</table>

### SMBaudit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The audit view is one of the three tabs of the web panel. It is accessed through <code>http://localhost:3092/?tab=audit</code>.</p>
      <p>The audit view reads <code>/var/log/samba/log.audit</code> and its rotated files. <code>smbapi.php</code> returns the records as JSON. The maximum number returned per request is set by <code>MAX_LOG_LINES</code> in <code>smbstack.env</code>.</p>
      <p>Date, IP, action and text filters are applied in the browser to the records already received. You can view the results in pages of 50, 100, 200 or 500 records.</p>
      <p>The <strong>Export PDF</strong> button opens the browser's print window with three columns: date and time, IP and file. You can save or print the document there; the server does not generate the PDF.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>La vista de auditoría es una de las tres pestañas del panel web. Se accede mediante <code>http://localhost:3092/?tab=audit</code>.</p>
      <p>La vista consulta <code>/var/log/samba/log.audit</code> y sus archivos rotados. <code>smbapi.php</code> lee los registros y los entrega en formato JSON. El máximo por petición se configura con <code>MAX_LOG_LINES</code> en <code>smbstack.env</code>.</p>
      <p>Los filtros de fecha, IP, acción y texto se aplican en el navegador a los registros recibidos. Puedes ver los resultados en páginas de 50, 100, 200 o 500 registros.</p>
      <p>El botón <strong>Export PDF</strong> abre la ventana de impresión del navegador con tres columnas: fecha y hora, IP y archivo. Desde allí puedes guardar o imprimir el documento; el servidor no genera el PDF.</p>
    </td>
  </tr>
</table>

[![smbaudit](./img/smbaudit.png)](https://github.com/maravento/smbstack)

[![smbstack-botton](./img/smbstack-botton.png)](https://github.com/maravento/smbstack)

### SMBshared

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The web panel is an Apache VirtualHost listening on port <code>3092</code>. It is accessed through <code>http://localhost:3092/</code> and has three tabs: <strong>Shared</strong>, <strong>Audit</strong> and <strong>Report</strong>. Each tab corresponds to a separate page, which <code>index.php</code> loads inside a frame.</p>
      <p>The <strong>Shared</strong> tab displays the contents of the shared folder. From there a document can be opened, downloaded or moved to the recycle bin.</p>
      <p>The root of the shared folder is read-only: you cannot upload files, create folders or delete items there. These actions are available inside subfolders.</p>
      <p>Apache runs the panel as the <code>www-data</code> user, which receives read and write permissions on the shared folder through an ACL set during the installation.</p>
      <p>The light and dark themes are selected from the top bar. The selection is stored in the browser and applied to the three tabs.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>El panel web es un VirtualHost de Apache que escucha en el puerto <code>3092</code>. Se accede mediante <code>http://localhost:3092/</code> y tiene tres pestañas: <strong>Shared</strong>, <strong>Audit</strong> y <strong>Report</strong>. Cada pestaña corresponde a una página independiente, que <code>index.php</code> carga dentro de un marco.</p>
      <p>La pestaña <strong>Shared</strong> muestra el contenido de la carpeta compartida. Desde allí se puede abrir un documento, descargarlo o moverlo a la papelera de reciclaje.</p>
      <p>La raíz de la carpeta compartida es de solo lectura: desde allí no puedes subir archivos, crear carpetas ni eliminar elementos. Estas acciones están disponibles dentro de las subcarpetas.</p>
      <p>Apache ejecuta el panel como el usuario <code>www-data</code>, que recibe permisos de lectura y escritura sobre la carpeta compartida mediante una ACL establecida durante la instalación.</p>
      <p>Los temas claro y oscuro se seleccionan desde la barra superior. La selección se guarda en el navegador y se aplica a las tres pestañas.</p>
    </td>
  </tr>
</table>

[![smbshared](./img/smbshared.png)](https://github.com/maravento/smbstack)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li>Inside a subfolder, the toolbar allows uploading one or more files, creating folders and reloading the view. Each operation is recorded in the audit log together with the client's IP address.</li>
        <li>Images and PDF files open in a modal through the <strong>Preview</strong> button, without being downloaded. For the remaining file types, the <strong>View</strong> button is kept, which opens the file in a new tab.</li>
        <li>Files can be uploaded through the file selector or by dropping them on the upload panel. A progress bar reports the state of the transfer.</li>
        <li>The panel can be installed as a Progressive Web App (PWA) on Chrome, Edge and Safari. Offline, only the app shell is available; access to files requires a connection. Firefox Desktop does not offer the installation option, so the panel works there as a regular web page.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li>Dentro de una subcarpeta, la barra de herramientas permite subir uno o varios archivos, crear carpetas y recargar la vista. Cada operación queda registrada en el registro de auditoría junto con la IP del cliente.</li>
        <li>Las imágenes y los archivos PDF se abren en un modal mediante el botón <strong>Preview</strong>, sin descargarlos. Para los demás tipos de archivo se mantiene el botón <strong>View</strong>, que abre el archivo en una pestaña nueva.</li>
        <li>Los archivos pueden subirse mediante el selector de archivos o soltándolos sobre el panel de subida. Una barra de progreso informa del estado de la transferencia.</li>
        <li>Puedes instalar el panel como aplicación web progresiva (PWA) en Chrome, Edge y Safari. Sin conexión solo queda disponible la estructura de la aplicación; para acceder a los archivos se necesita conexión. Firefox para escritorio no ofrece la opción de instalación, por lo que el panel funciona allí como una página web normal.</li>
      </ul>
    </td>
  </tr>
</table>

[![smbstack-files](./img/smbstack-files.png)](https://github.com/maravento/smbstack)

### SMBreport

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The report view is the third tab of the web panel. It is accessed through <code>http://localhost:3092/?tab=report</code>.</p>
      <p>It contains three tables: the thirty extensions with the largest total size, the thirty folders with the largest total size, and the fifty largest files, with their full path. The extensions table includes the file count, the average size and the share they represent of the total.</p>
      <p><code>tools/smbreport.sh</code> walks the shared folder as <code>root</code> and saves the results in a JSON file. Cron runs the script daily at 03:00. Because the walk can take several minutes and use the disk while SMB clients are working, it is scheduled outside working hours.</p>
      <p>The view requests the data from <code>smbapi.php</code>; it does not scan the disk. Until <code>smbreport.sh</code> completes its first scan, the tab reports that no report is available.</p>
      <p>The report excludes the recycle bin, so its files do not appear in the tables. The JSON file is also unavailable over HTTP: <code>smbapi.php</code> reads it directly from disk instead of serving it from Apache's web root.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>La vista de informe es la tercera pestaña del panel web. Se accede mediante <code>http://localhost:3092/?tab=report</code>.</p>
      <p>Contiene tres tablas: las treinta extensiones con mayor tamaño total, las treinta carpetas con mayor tamaño total y los cincuenta archivos más grandes, con su ruta completa. La tabla de extensiones incluye el número de archivos, el tamaño promedio y la proporción que representan sobre el total.</p>
      <p><code>tools/smbreport.sh</code> recorre la carpeta compartida como <code>root</code> y guarda los resultados en un archivo JSON. Cron ejecuta el script cada día a las 03:00. Como el recorrido puede tardar varios minutos y usar el disco mientras trabajan los clientes SMB, se programa fuera del horario laboral.</p>
      <p>La vista solicita los datos a <code>smbapi.php</code>; no recorre el disco. Hasta que <code>smbreport.sh</code> complete el primer recorrido, la pestaña indicará que aún no hay un informe disponible.</p>
      <p>El informe no incluye la papelera, por lo que sus archivos no aparecen en las tablas. El archivo JSON tampoco está disponible por HTTP: <code>smbapi.php</code> lo lee directamente del disco y no lo publica en la raíz web de Apache.</p>
    </td>
  </tr>
</table>

[![smbreport](./img/smbreport.png)](https://github.com/maravento/smbstack)

## SCOPE

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>What SMBstack does:</b>
      <ul>
        <li>Installs and configures Samba with a shared folder, recycle bin and group permissions.</li>
        <li>Configures audit logging through <code>rsyslog</code> to <code>/var/log/samba/log.audit</code>.</li>
        <li>Deploys a web panel with three tabs at <code>http://localhost:3092/</code>: shared folder, audit log and disk usage report.</li>
        <li>Configures <code>logrotate</code> for the Samba logs.</li>
        <li>Installs the <code>smbload.sh</code> service monitor, which cron runs every five minutes.</li>
        <li>Includes <code>smbwatch.sh</code>, a shared folder size monitor managed separately from the installer.</li>
        <li>Provides a configuration backup tool (<code>smbbk.sh</code>), run through cron monthly.</li>
        <li>Installs a disk usage report (<code>smbreport.sh</code>), run through cron daily at 03:00.</li>
        <li>Saves the installation configuration to <code>/var/www/smbstack/smbstack.env</code> for future updates.</li>
        <li>Keeps NetBIOS disabled by default. It can be enabled manually if required; see the NetBIOS section.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Lo que SMBstack hace:</b>
      <ul>
        <li>Instala y configura Samba con una carpeta compartida, papelera de reciclaje y permisos de grupo.</li>
        <li>Configura la auditoría mediante <code>rsyslog</code> en <code>/var/log/samba/log.audit</code>.</li>
        <li>Despliega un panel web con tres pestañas en <code>http://localhost:3092/</code>: carpeta compartida, registro de auditoría e informe de uso de disco.</li>
        <li>Configura <code>logrotate</code> para los registros de Samba.</li>
        <li>Instala el supervisor de servicios <code>smbload.sh</code>, que cron ejecuta cada cinco minutos.</li>
        <li>Incluye <code>smbwatch.sh</code>, un monitor de espacio que se administra por separado y no depende del instalador.</li>
        <li>Proporciona una herramienta de respaldo de configuración (<code>smbbk.sh</code>), ejecutada mediante cron mensualmente.</li>
        <li>Instala un informe de uso de disco (<code>smbreport.sh</code>), ejecutado mediante cron diariamente a las 03:00.</li>
        <li>Guarda la configuración de la instalación en <code>/var/www/smbstack/smbstack.env</code> para futuras actualizaciones.</li>
        <li>Mantiene NetBIOS deshabilitado por defecto. Puede activarse manualmente si es necesario; consulte la sección NetBIOS.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>Out of scope (not implemented):</b>
      <ul>
        <li>Active Directory / domain controller.</li>
        <li>Multiple shared folders.</li>
        <li>Custom paths outside <code>/home/$local_user/</code> (require manual editing).</li>
        <li>IPv6.</li>
        <li>LDAP.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Fuera de alcance (no implementado):</b>
      <ul>
        <li>Active Directory / controlador de dominio.</li>
        <li>Múltiples carpetas compartidas.</li>
        <li>Rutas personalizadas fuera de <code>/home/$local_user/</code> (requieren edición manual).</li>
        <li>IPv6.</li>
        <li>LDAP.</li>
      </ul>
    </td>
  </tr>
</table>

## REPOSITORY STRUCTURE

---

```
smbstack/
├── acl/                         # Static access-control lists for Samba
│   └── commonveto.txt              # Veto list for common unwanted file types (active by default in smb.conf)
│
├── conf/                        # Samba and rsyslog configuration
│   ├── fullaudit.conf              # rsyslog full audit rule
│   └── smb.conf                    # Samba main config (placeholders: your_user, compartida)
│
├── tools/                      # Background watchdog and maintenance scripts
│   ├── smbbk.sh                    # Configuration backup for smbstack
│   ├── smbload.sh                  # Service watchdog (smbd + winbind + smbwatch)
│   ├── smbreport.sh                # Disk usage report for the shared folder (daily cron)
│   └── smbwatch.sh                 # Shared folder size monitor (self-managed)
│
├── web/                        # Web front-end: shared-folder browser, audit log viewer and disk report
│   ├── icon.svg                    # PWA / apple-touch icon
│   ├── index.php                   # Main page (Shared / Audit / Report tabs)
│   ├── manifest.json               # PWA manifest
│   ├── smbshared.php               # Shared folder dynamic browser
│   ├── smbapi.php                  # Audit log and disk report reader API
│   ├── smbaudit-diagnostic.php     # Audit log diagnostic tool
│   ├── smbaudit.html               # Audit log viewer UI
│   ├── smbreport.html              # Disk report viewer UI
│   ├── smbweb.conf                 # Apache vhost (:3092/?tab=shared, ?tab=audit and ?tab=report)
│   └── sw.js                       # PWA service worker (app-shell cache only)
│
└── smbsetup.sh                 # Installer: install, update, uninstall, status
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
├── .size_cache/                # Folder size cache used by smbshared.php (www-data, pruned daily by cron)
├── tools/                      # Deployed copy of tools/*.sh
├── web/                        # Deployed copy of web/ (served by Apache on :3092)
│   └── smbreport.json          # Disk report written by tools/smbreport.sh (root:www-data, 640)
└── smbstack.env                # Saved install config (user, paths, network, trusted proxies, watch limit, max log lines)

/etc/bak/smbstack/              # Archives written by tools/smbbk.sh (smbbk_<YYYYMMDD_HHMM>.zip, last 3 kept),
                                # run by --update before overwriting application code, and by its own monthly cron
/etc/cron.d/smbstack            # All cron entries of the project, one file

/var/log/smbwatch.log           # smbwatch.sh runtime log (root:root, 640)
/var/log/smbload.log            # smbload.sh runtime log
/var/log/smbstack.log           # smbbk.sh and smbreport.sh runtime log, shared

/home/$local_user/shared/       # Shared folder (independent of the installer)
├── .recycle/                   # Recycle Bin (smbguest/, www-data/, smbwatch/)
└── DEMO/                       # Demo folder

/etc/logrotate.d/samba          # Generated by installer (heredoc)
/etc/logrotate.d/smbwatch       # Generated by installer (heredoc), rotates /var/log/smbwatch.log
/var/log/samba/log.audit        # Created by rsyslog
/var/log/samba/log.samba        # Created by installer, written directly by smbd

/etc/samba/acl/commonveto.txt   # Copied from acl/commonveto.txt by the installer
```

> Every cron entry of the project lives in `/etc/cron.d/smbstack`. `smbsetup.sh`, `tools/smbwatch.sh`, `tools/smbreport.sh` and `tools/smbbk.sh` add or remove their own line in that file.
>
> Each line names the user that runs the task, as required by the `/etc/cron.d` format. The scripts add or remove only their own entries in `/etc/cron.d/smbstack`.
>
> `--uninstall` deletes the file.
>
> Installations made before this change keep their entries in root's crontab. The installer removes them, identified by the full script path.
>
> Todas las entradas de cron del proyecto viven en `/etc/cron.d/smbstack`. `smbsetup.sh`, `tools/smbwatch.sh`, `tools/smbreport.sh` y `tools/smbbk.sh` agregan o eliminan su propia línea en ese archivo.
>
> Cada línea indica el usuario que ejecutará la tarea, como requiere el formato de `/etc/cron.d`. Los scripts agregan o eliminan únicamente sus propias entradas en `/etc/cron.d/smbstack`.
>
> `--uninstall` elimina el archivo.
>
> Las instalaciones anteriores a este cambio conservan sus entradas en el crontab de root. El instalador las retira, identificadas por la ruta completa del script.

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
sudo bash smbsetup.sh
# or, to skip the menu and install directly | o, para saltar el menú e instalar directamente
sudo bash smbsetup.sh --install
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer will prompt for:
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador preguntará por:
    </td>
  </tr>
</table>

| Prompt | Description | Descripción |
|--------|-------------|-------------|
| Shared folder name | Name for the shared folder (created under `/home/$local_user/`) | Nombre de la carpeta compartida (creada bajo `/home/$local_user/`) |
| Network interface | Selected from available interfaces listed. The Samba network is derived from its address and prefix | Seleccionada de las interfaces disponibles listadas. La red de Samba se deriva de su dirección y prefijo |
| Samba username | Samba account to create | Cuenta de Samba a crear |
| Overwrite smb.conf | Only asked if `/etc/samba/smb.conf` already exists | Solo se pregunta si `/etc/samba/smb.conf` ya existe |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>Set <code>SMBSTACK_IFACE</code> to skip the interactive interface selection. For example:</p>
      <p><code>sudo SMBSTACK_IFACE=eth1 bash smbsetup.sh --install</code></p>
      <p>Another installer deploying SMBstack can use this variable to provide the interface it already knows.</p>
      <p><code>$local_user</code> is the local Linux user that the installer detects automatically.</p>
      <p>The installer looks for an account whose UID falls within the range in <code>/etc/login.defs</code>, whose login shell is enabled and that belongs to the <code>sudo</code> group. If several accounts match, it selects the one with the lowest UID.</p>
      <p>That account owns the shared folder and provides the base name for the Samba username.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Define <code>SMBSTACK_IFACE</code> para omitir la selección interactiva de la interfaz. Por ejemplo:</p>
      <p><code>sudo SMBSTACK_IFACE=eth1 bash smbsetup.sh --install</code></p>
      <p>Otro instalador que despliega SMBstack puede utilizar esta variable para proporcionar la interfaz que ya conoce.</p>
      <p><code>$local_user</code> es el usuario local de Linux que el instalador detecta automáticamente.</p>
      <p>El instalador busca una cuenta con UID dentro del rango de <code>/etc/login.defs</code>, una shell habilitada y pertenencia al grupo <code>sudo</code>. Si encuentra varias, elige la de UID más bajo.</p>
      <p>Usa esa cuenta como propietaria de la carpeta compartida y como base para el nombre de usuario de Samba.</p>
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
sudo bash smbsetup.sh --update
# or | o
sudo bash smbsetup.sh --uninstall
```

| File | `--update` | `--uninstall` |
|------|-----------|---------------|
| `conf/smb.conf` | ⛔ not touched (user-customized) | ✅ restored from `.bak` if it exists (only created when the installer overwrote a pre-existing `smb.conf`; on a fresh install, no `.bak` exists and `smb.conf` is left untouched) |
| `conf/fullaudit.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/smbweb.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/index.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit.html` | ✅ overwritten | ✅ removed |
| `web/smbapi.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit-diagnostic.php` | ✅ overwritten | ✅ removed |
| `web/smbshared.php` | ✅ overwritten | ✅ removed |
| `web/manifest.json` | ✅ overwritten | ✅ removed |
| `web/sw.js` | ✅ overwritten | ✅ removed |
| `web/icon.svg` | ✅ overwritten | ✅ removed |
| `tools/smbbk.sh` | ✅ overwritten | ✅ removed (its cron entry is deregistered first) |
| `tools/smbload.sh` | ✅ overwritten | ✅ removed |
| `tools/smbwatch.sh` | ✅ overwritten | ✅ removed |
| `/var/www/smbstack/smbstack.env` | ⛔ preserved | ✅ removed |
| Shared folder (`/home/$local_user/shared/`) | ⛔ never touched | ⛔ never touched |

> The shared folder is independent of the installer. To remove it, do so manually: `rm -rf /home/$local_user/shared`
>
> La carpeta compartida es independiente del instalador. Para eliminarla, hazlo manualmente: `rm -rf /home/$local_user/shared`

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>Before updating files, <code>--update</code> runs <code>tools/smbbk.sh</code>, which saves a backup in <code>/etc/bak/smbstack</code>.</p>
      <p>It only updates the application code: the web viewers in PHP and HTML and <code>tools/*.sh</code>.</p>
      <p>The configuration files deployed during the installation, <code>smb.conf</code>, <code>fullaudit.conf</code> and <code>smbweb.conf</code>, are never overwritten, since they may contain manual edits such as custom shares, <code>hosts allow</code> or interfaces.</p>
      <p>To incorporate changes to those files after an update, compare them with the versions in <code>conf/</code> and <code>web/smbweb.conf</code> in the repository, then apply the ones you need manually.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Antes de actualizar los archivos, <code>--update</code> ejecuta <code>tools/smbbk.sh</code>, que guarda un respaldo en <code>/etc/bak/smbstack</code>.</p>
      <p>Solo actualiza el código de la aplicación: los visores web en PHP y HTML y <code>tools/*.sh</code>.</p>
      <p>Los archivos de configuración desplegados en la instalación, <code>smb.conf</code>, <code>fullaudit.conf</code> y <code>smbweb.conf</code>, nunca se sobrescriben, ya que pueden contener ediciones manuales como shares personalizados, <code>hosts allow</code> o interfaces.</p>
      <p>Para incorporar cambios en esos archivos después de actualizar, compáralos con las versiones de <code>conf/</code> y <code>web/smbweb.conf</code> del repositorio y aplica manualmente los que necesites.</p>
    </td>
  </tr>
</table>

### Status

```bash
sudo bash smbsetup.sh --status
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>Shows the status of the <code>smbd</code> and <code>winbind</code> services, the status of Apache port <code>3092</code>, the last five audit log entries and a <code>testparm</code> summary.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Muestra el estado de los servicios <code>smbd</code> y <code>winbind</code>, el estado del puerto <code>3092</code> de Apache, las últimas cinco entradas del registro de auditoría y un resumen de <code>testparm</code>.</p>
    </td>
  </tr>
</table>

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
| Log rotation (Samba logs) | `/etc/logrotate.d/samba` |
| Log rotation (`smbwatch.sh`) | `/etc/logrotate.d/smbwatch` |
| Install config | `/var/www/smbstack/smbstack.env` |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbstack.env</code> sets <code>TRUSTED_PROXIES="127.0.0.1"</code> by default.</p>
      <p>This setting tells <code>web/smbshared.php</code> that, for requests arriving from <code>localhost</code>, it must use the <code>CF-Connecting-IP</code> or <code>X-Forwarded-For</code> header, when present, instead of <code>REMOTE_ADDR</code>. This way the loopback connection of a local tunnel is not recorded as the client address in the audit log.</p>
      <p>The setting has no effect on direct access from the LAN.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbstack.env</code> establece <code>TRUSTED_PROXIES="127.0.0.1"</code> por defecto.</p>
      <p>Esta configuración indica a <code>web/smbshared.php</code> que, para las solicitudes que llegan desde <code>localhost</code>, utilice el encabezado <code>CF-Connecting-IP</code> o <code>X-Forwarded-For</code>, cuando esté presente, en lugar de <code>REMOTE_ADDR</code>. De esta forma, la conexión loopback de un túnel local no se registra como la dirección del cliente en el registro de auditoría.</p>
      <p>La configuración no tiene efecto sobre el acceso directo desde la LAN.</p>
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
      <p>To use a shared folder located outside <code>/home/$local_user/</code>, edit <code>/etc/samba/smb.conf</code> and <code>/etc/apache2/sites-available/smbweb.conf</code> manually after the installation.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Para utilizar una carpeta compartida ubicada fuera de <code>/home/$local_user/</code>, edita manualmente <code>/etc/samba/smb.conf</code> y <code>/etc/apache2/sites-available/smbweb.conf</code> después de la instalación.</p>
    </td>
  </tr>
</table>

### Recycle Bin

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack uses the Samba <code>vfs_recycle</code> module to redirect deleted files to a hidden recycle bin, instead of removing them permanently. The bin is stored inside the shared folder, under <code>.recycle/</code>.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack utiliza el módulo <code>vfs_recycle</code> de Samba para redirigir los archivos eliminados a una papelera de reciclaje oculta, en lugar de borrarlos permanentemente. Esta se almacena dentro de la carpeta compartida, en <code>.recycle/</code>.</p>
    </td>
  </tr>
</table>

#### Recycle bin channels

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack uses three independent channels to write to the recycle bin, each running under a different system context:</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack utiliza tres canales independientes para escribir en la papelera de reciclaje, cada uno ejecutándose bajo un contexto de sistema diferente:</p>
    </td>
  </tr>
</table>

| Path | Written by | Purpose | Propósito |
|---|---|---|---|
| `.recycle/smbguest/` | SMB clients on the LAN, through `vfs_recycle` (`smbguest`, set by `force user` in `smb.conf`) | Holds files deleted by users from Windows or Linux over the network | Guarda los archivos borrados por los usuarios desde Windows o Linux por la red |
| `.recycle/www-data/` | The web interface running under Apache (`www-data`) | Holds files deleted from the browser panel | Guarda los archivos borrados desde el panel web |
| `.recycle/smbwatch/` | `tools/smbwatch.sh` (`${LOCAL_USER:-root}:sambashare`) | Holds files moved out automatically when a monitored folder exceeds its size limit | Guarda los archivos retirados automáticamente cuando una carpeta monitoreada supera su límite de tamaño |

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

> the recycle bin lives inside the shared folder itself, so that recycling a file is a `mv` within the same filesystem: instantaneous and without copying data, something that would not happen if the bin were on another disk. For the details of each channel, see the *Web Interface*, *smbwatch* and *Configuration reference* sections.

> la papelera vive dentro de la propia carpeta compartida para que reciclar un archivo sea un `mv` dentro del mismo sistema de archivos: instantáneo y sin copiar datos, algo que no ocurriría si la papelera estuviera en otro disco. Para conocer el detalle de cada canal, consulta las secciones *Web Interface*, *smbwatch* y *Configuration reference*.

#### Recycle timestamp

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The weekly cleanup deletes items based on their modification date. Each channel therefore updates that date when moving an item to the recycle bin. Otherwise, an old file could be deleted during the next cleanup even though it had only just been recycled.</p>
      <p>Each channel updates the item's modification date with the current date when moving it to the bin:</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>La limpieza semanal elimina elementos según su fecha de modificación. Por eso, al mover un archivo a la papelera, cada canal actualiza esa fecha. Si se conservara la fecha original, un archivo antiguo podría eliminarse en la siguiente limpieza aunque acabara de reciclarse.</p>
      <p>Cada canal actualiza la fecha de modificación del elemento con la fecha actual al moverlo a la papelera:</p>
    </td>
  </tr>
</table>

| Channel | Stamped by |
|---------|------------|
| SMB (LAN clients) | `recycle:touch = yes` in `smb.conf` |
| Web interface (Apache) | `recycle_touch()` in `web/smbshared.php`, applied recursively so a recycled folder carries its contents |
| Size-limit watchdog | `touch` after the move, in `tools/smbwatch.sh` |

> A restored item therefore carries the date it was recycled, not its original one.
>
> Por eso un elemento restaurado conserva la fecha en que fue reciclado, no la original.

#### File versioning

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>When <code>recycle:versions = yes</code> is active, deleting a file that already exists in the recycle bin does not overwrite it. The new copy is kept alongside the original with the <code>Copy #N of</code> prefix:</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Cuando <code>recycle:versions = yes</code> está activo, eliminar un archivo que ya existe en la papelera no lo sobrescribe. La nueva copia se conserva junto a la original con el prefijo <code>Copy #N of</code>:</p>
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

| Parameter | Value | Purpose | Propósito |
|-----------|-------|---------|-----------|
| `recycle:repository` | `.recycle/%U` | SMB channel recycle bin, resolves to `smbguest` | Papelera del canal SMB, resuelve a `smbguest` |
| `recycle:directory_mode` | `0775` | Group-writable recycle directory | Directorio escribible por el grupo |
| `recycle:keeptree` | `yes` | Preserve original folder structure | Preservar estructura de carpetas |
| `recycle:versions` | `yes` | Keep multiple versions of deleted files | Mantener múltiples versiones |
| `recycle:noversions` | `*.dat,*.ini` | Exclude patterns from versioning | Excluir patrones del versionado |
| `recycle:touch` | `yes` | Update access time when recycled | Actualizar tiempo de acceso al reciclar |
| `recycle:exclude` | `*.tmp,*.temp,*.o,…` | Permanently delete matching files | Eliminar permanentemente archivos que coincidan |
| `recycle:exclude_dir` | `/temp,/tmp,/cache,/.Trash-1000` | Bypass recycle bin for directories | Omitir papelera para directorios |
| `recycle:maxsize` | `1073741824` | Max file size (1 GB) | Tamaño máximo (1 GB) |
| `hide files` | `/.recycle/` | Hide recycle directory from clients | Ocultar papelera a los clientes |

#### Automatic cleanup

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The installer registers a weekly cron job, run as <code>root</code>, that removes recycled files older than 7 days:</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>El instalador registra una tarea cron semanal, ejecutada como <code>root</code>, que elimina los archivos reciclados con más de 7 días de antigüedad:</p>
    </td>
  </tr>
</table>

```bash
@weekly root find "/home/$local_user/shared/.recycle/" -depth -mindepth 1 -mtime +6 -delete >/dev/null 2>&1
```

> The cleanup runs once a week and removes items older than six days, so an item remains in the bin for 7 to almost 14 days, depending on when it was moved there.
>
> Como la limpieza se ejecuta una vez por semana y elimina elementos con más de seis días, estos permanecen en la papelera entre 7 y casi 14 días, según cuándo se hayan movido allí.

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To adjust the retention period, edit the project cron file. To inspect its entries, display the file:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para ajustar el período de retención, edita el archivo de tareas del proyecto. Para consultar sus entradas, muestra el archivo:
    </td>
  </tr>
</table>

```bash
# Edit project cron entries
sudo nano /etc/cron.d/smbstack

# Inspect project cron entries
sudo cat /etc/cron.d/smbstack
```

---

### Full Audit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack uses the Samba <code>vfs_full_audit</code> module to record file operations in <code>/var/log/samba/log.audit</code> through <code>rsyslog</code>. Only successful operations are recorded; failures are excluded to keep the log clean.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>SMBstack utiliza el módulo <code>vfs_full_audit</code> de Samba para registrar las operaciones de archivos en <code>/var/log/samba/log.audit</code> mediante <code>rsyslog</code>. Solo se registran las operaciones exitosas; los fallos se excluyen para mantener el registro limpio.</p>
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
        <li><b><code>renameat</code> format:</b> recorded as <code>source_path|destination_path</code>. This operation does not appear for recycle bin operations.</li>
        <li><b>Recycled vs. permanently deleted:</b> <code>unlinkat</code> does not allow telling both operations apart, since <code>vfs_full_audit</code> intercepts the call before <code>vfs_recycle</code> redirects it. To determine what happened, check the <code>.recycle/</code> directory on the filesystem.</li>
        <li><b><code>pwrite</code> source:</b> it can be recorded both by Samba (SMB clients) and by <code>smbshared.php</code> (uploads from the web interface, which do not go through <code>smbd</code>). To tell them apart, check the syslog <code>$user</code> field before <code>smbd_audit:</code>; the web interface always records it as <code>www-data</code>.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li><b>Formato de <code>renameat</code>:</b> se registra como <code>ruta_origen|ruta_destino</code>. Esta operación no aparece en las operaciones de la papelera de reciclaje.</li>
        <li><b>Reciclado vs. eliminación permanente:</b> <code>unlinkat</code> no permite distinguir entre ambas operaciones, ya que <code>vfs_full_audit</code> intercepta la llamada antes de que <code>vfs_recycle</code> la redirija. Para determinar qué ocurrió, comprueba el directorio <code>.recycle/</code> en el sistema de archivos.</li>
        <li><b>Origen de <code>pwrite</code>:</b> puede ser registrado tanto por Samba (clientes SMB) como por <code>smbshared.php</code> (subidas desde la interfaz web, que no pasan por <code>smbd</code>). Para distinguirlos, revisa el campo <code>$user</code> de syslog antes de <code>smbd_audit:</code>; la interfaz web siempre lo registra como <code>www-data</code>.</li>
      </ul>
    </td>
  </tr>
</table>

##### Why `openat` is not audited

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>openat</code> was evaluated and excluded from <code>full_audit:success</code> by default.</p>
      <p>Every file or directory open generates an entry, including browsing, reads and downloads, not only writes. A single Explorer window open on a busy folder can produce dozens of near-identical lines per second.</p>
      <p>This volume of records can hide the events actually worth reviewing, and adds no further traceability, since <code>pwrite</code> records the write itself.</p>
      <p>This is a project configuration decision, not a Samba limitation. To audit opens and reads as well, add it manually in <code>/etc/samba/smb.conf</code>:</p>
      <p><code>full_audit:success = mkdirat renameat unlinkat pwrite openat</code></p>
      <p>Then run <code>testparm</code> and <code>systemctl restart smbd</code>. <code>--update</code> will not modify this setting: <code>smb.conf</code> is not overwritten after the installation, so the change is preserved.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Se evaluó y se decidió excluir <code>openat</code> de <code>full_audit:success</code> por defecto.</p>
      <p>Cada apertura de archivo o carpeta genera una entrada, incluida la navegación, las lecturas y las descargas, no solo las escrituras. Una sola ventana del Explorador abierta sobre una carpeta con actividad puede producir decenas de líneas casi idénticas por segundo.</p>
      <p>Este volumen de registros puede ocultar los eventos que sí conviene revisar y no aporta trazabilidad adicional, ya que <code>pwrite</code> registra la escritura propiamente dicha.</p>
      <p>Esta es una decisión de configuración del proyecto, no una limitación de Samba. Para auditar también las aperturas y lecturas, agréguelo manualmente en <code>/etc/samba/smb.conf</code>:</p>
      <p><code>full_audit:success = mkdirat renameat unlinkat pwrite openat</code></p>
      <p>Luego, ejecute <code>testparm</code> y <code>systemctl restart smbd</code>. <code>--update</code> no modificará este ajuste: <code>smb.conf</code> no se sobrescribe después de la instalación, por lo que el cambio se conserva.</p>
    </td>
  </tr>
</table>

---

### smbload

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbload.sh</code> is a service watchdog that checks that <code>smbd</code> and <code>winbind</code> are running. Neither unit has a <code>Restart=</code> policy configured, so they are not restarted automatically when they stop.</p>
      <p>It also checks that <code>smbwatch.sh</code> is still running and restarts it if it has stopped.</p>
      <p>The installer adds <code>smbload.sh</code> to cron automatically. It runs every five minutes from <code>/var/www/smbstack/tools/</code>.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbload.sh</code> es un watchdog de servicios que comprueba que <code>smbd</code> y <code>winbind</code> estén en ejecución. Ninguna de las dos unidades tiene configurada una política <code>Restart=</code>, por lo que no se reinician automáticamente cuando se detienen.</p>
      <p>También comprueba que <code>smbwatch.sh</code> siga ejecutándose y lo reinicia si ha dejado de hacerlo.</p>
      <p>El instalador registra automáticamente <code>smbload.sh</code> en cron para que se ejecute cada cinco minutos desde <code>/var/www/smbstack/tools/</code>.</p>
    </td>
  </tr>
</table>

```bash
# sudo cat /etc/cron.d/smbstack
*/5 * * * * root /var/www/smbstack/tools/smbload.sh
```

> `smbload.sh` reads no configuration of its own. It only checks whether the watcher is running and calls `smbwatch.sh start` if it is not. Until `smbwatch.sh install` has been run from a terminal, that call aborts on its own key check, so `smbload.sh` logs a `-- alert` warning pointing at `smbwatch.log`, where the missing or invalid key is named.

> `smbload.sh` no lee configuración propia. Solo comprueba si el vigilante corre y llama a `smbwatch.sh start` si no. Hasta que se haya ejecutado `smbwatch.sh install` desde un terminal, esa llamada aborta en su propia verificación de claves, así que `smbload.sh` registra un aviso `-- alert` que apunta a `smbwatch.log`, donde se nombra la clave que falta o es inválida.

### smbwatch

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbwatch.sh</code> monitors first-level subfolders and their contents in real time with <code>inotifywait</code>.</p>
      <p>If a folder exceeds its configured size limit, a newly completed or moved-in file is moved to <code>.recycle/smbwatch/&lt;YYYYMMDD&gt;/</code>. This channel is separate from <code>.recycle/smbguest/</code> and <code>.recycle/www-data/</code>. See <i>Recycle bin channels</i>.</p>
      <p><code>smbwatch.sh</code> is managed independently of the installer, through five actions: <code>install</code>, <code>uninstall</code>, <code>start</code>, <code>stop</code> and <code>status</code>.</p>
      <p><code>install</code> is the only action that changes <code>smbstack.env</code>: it asks for the two values, registers the <code>@reboot</code> entry and starts the watcher. It requires an interactive terminal and is run once. <code>uninstall</code> stops the watcher, removes its cron entry and deletes the two values.</p>
      <p><code>start</code> never writes: it validates the keys and launches the watcher. If a key is missing or invalid it aborts, naming each failure and telling the operator to run <code>install</code> first. This is the action cron runs on every boot, and the one <code>smbload.sh</code> uses to restart a stopped watcher.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbwatch.sh</code> vigila en tiempo real las carpetas de primer nivel y su contenido mediante <code>inotifywait</code>.</p>
      <p>Si una carpeta supera el límite configurado, mueve a <code>.recycle/smbwatch/&lt;AAAAMMDD&gt;/</code> los archivos que acaban de terminar de escribirse o que acaban de llegar. Este canal es independiente de <code>.recycle/smbguest/</code> y <code>.recycle/www-data/</code>. Consulta la sección <i>Recycle bin channels</i>.</p>
      <p><code>smbwatch.sh</code> se administra de forma independiente del instalador, mediante cinco acciones: <code>install</code>, <code>uninstall</code>, <code>start</code>, <code>stop</code> y <code>status</code>.</p>
      <p><code>install</code> es la única acción que modifica <code>smbstack.env</code>: solicita los dos valores, registra el inicio automático con <code>@reboot</code> y arranca el monitor. Requiere una terminal interactiva y se ejecuta una vez. <code>uninstall</code> detiene el monitor, elimina la entrada de cron y borra esos dos valores.</p>
      <p><code>start</code> nunca escribe: valida las claves y lanza el vigilante. Si falta una clave o es inválida, aborta nombrando cada fallo e indicando que se ejecute <code>install</code> primero. Esta es la acción que cron ejecuta en cada arranque, y la que usa <code>smbload.sh</code> para reiniciar un vigilante detenido.</p>
    </td>
  </tr>
</table>

| `smbstack.env` variable | Default | Purpose | Propósito |
|---|---|---|---|
| `WATCH_LIMIT_GB` | `10` | Size limit per monitored folder, in GB | Límite de tamaño por carpeta monitoreada, en GB |
| `WATCH_EXCLUDE` | `NONE` | Comma-separated folder names excluded from monitoring (e.g. `FINANCE,LEGAL`) | Nombres de carpetas separados por comas excluidas del monitoreo |

> The watcher checks a file when writing finishes or when the file arrives by a move or rename. This prevents a file moved from an excluded folder from bypassing the limit. Renaming a file inside a folder that is already over the limit also sends it to the recycle bin. Moving an entire folder is not monitored.
>
> smbwatch revisa los archivos cuando termina su escritura o cuando llegan por movimiento o renombrado; por eso, mover un archivo desde una carpeta excluida no evita el límite. Si renombras un archivo dentro de una carpeta que ya superó el límite, también se moverá a la papelera. El monitor no detecta el traslado de una carpeta completa.

```bash
# Install (interactive: asks for the two keys, writes them, adds the @reboot
# cron entry and starts the watcher). Run this once, from a terminal.
sudo /var/www/smbstack/tools/smbwatch.sh install

# Start
sudo /var/www/smbstack/tools/smbwatch.sh start

# Stop
sudo /var/www/smbstack/tools/smbwatch.sh stop

# Status
sudo /var/www/smbstack/tools/smbwatch.sh status

# Uninstall (stops it, removes the cron entry and both keys)
sudo /var/www/smbstack/tools/smbwatch.sh uninstall
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>start</code> on a host where <code>install</code> was never run reports every missing key and then aborts, naming the action to run. It collects all the failures first, so one pass is enough to fix them:</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p><code>start</code> en un host donde nunca se ejecutó <code>install</code> informa cada clave que falta y luego aborta, nombrando la acción que debe ejecutarse. Recoge todos los fallos primero, así una sola pasada basta para corregirlos:</p>
    </td>
  </tr>
</table>

```text
ERROR: WATCH_LIMIT_GB missing line
ERROR: WATCH_EXCLUDE missing line
ERROR: 2 key(s) invalid in smbstack.env
ERROR: run 'smbwatch.sh install' first -- abort
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>The list of monitored folders is built once, when <code>smbwatch</code> starts. First-level folders can only be created by the administrator from the server shell, since SMB clients and the web panel cannot create them at the root of the shared folder.</p>
      <p>After adding a folder, restart <code>smbwatch</code> (<code>stop</code> and then <code>start</code>) so that it is included in the monitoring.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>La lista de carpetas monitoreadas se genera una sola vez al iniciar <code>smbwatch</code>. Las carpetas de primer nivel solo pueden ser creadas por el administrador desde el shell del servidor, ya que los clientes SMB y el panel web no pueden crearlas en la raíz de la carpeta compartida.</p>
      <p>Después de agregar una carpeta, reinicia <code>smbwatch</code> (<code>stop</code> y luego <code>start</code>) para que quede incluida en el monitoreo.</p>
    </td>
  </tr>
</table>

> `start` registers the `@reboot` entry in `/etc/cron.d/smbstack`, and `stop` removes it. A watcher stopped on purpose stays stopped across a reboot.
>
> `start` registra la entrada `@reboot` en `/etc/cron.d/smbstack`, y `stop` la elimina. Un vigilante detenido a propósito sigue detenido tras un reinicio.

### smbbk

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbbk.sh</code> creates a single compressed archive with SMBstack's configuration. It contains:</p>
      <ul>
        <li>The project install tree.</li>
        <li><code>smb.conf</code> and the audit ACL.</li>
        <li>Samba's private user database.</li>
        <li>The Apache VirtualHost and ports configuration.</li>
        <li>The <code>rsyslog</code> audit rule and the <code>logrotate</code> configurations.</li>
        <li>The <code>smbd.service</code> unit and the project cron file, <code>/etc/cron.d/smbstack</code>.</li>
        <li>A snapshot of the <code>smbguest</code> and <code>sambashare</code> users and groups.</li>
      </ul>
      <p>It does not back up the shared folder's data, the logs or the ACLs of the shared folder itself. It only keeps the configuration needed to reproduce the stack.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p><code>smbbk.sh</code> crea un único archivo comprimido con la configuración de SMBstack. Contiene:</p>
      <ul>
        <li>El árbol de instalación del proyecto.</li>
        <li><code>smb.conf</code> y la ACL de auditoría.</li>
        <li>La base de datos privada de usuarios de Samba.</li>
        <li>El VirtualHost y la configuración de puertos de Apache.</li>
        <li>La regla de auditoría de <code>rsyslog</code> y las configuraciones de <code>logrotate</code>.</li>
        <li>La unidad <code>smbd.service</code> y el archivo de tareas del proyecto, <code>/etc/cron.d/smbstack</code>.</li>
        <li>Una instantánea de los usuarios y grupos <code>smbguest</code> y <code>sambashare</code>.</li>
      </ul>
      <p>No respalda los datos de la carpeta compartida, los registros ni las ACL de la propia carpeta compartida. Solo conserva la configuración necesaria para reproducir el stack.</p>
    </td>
  </tr>
</table>

| Command | Description | Descripción |
|---|---|---|
| `sudo bash smbbk.sh` | Create a backup now | Crear una copia ahora |
| `sudo bash smbbk.sh install` | Register the `@monthly` cron entry | Registrar la entrada mensual en cron |
| `sudo bash smbbk.sh uninstall` | Remove the cron entry, keeping the archives | Quitar la entrada de cron, conservando los comprimidos |

> Backs up SMBstack into `/etc/bak/smbstack/smbbk_<YYYYMMDD_HHMM>.zip`, keeping up to 3 archives. Paths that do not exist are skipped. Restore by unzipping it over `/`.
>
> Respalda SMBstack en `/etc/bak/smbstack/smbbk_<YYYYMMDD_HHMM>.zip`, conservando hasta 3 comprimidos. Las rutas que no existan se omiten. Para restaurar, descomprímalo sobre `/`.

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>This project uses two kinds of backup, with different purposes and rules.</p>
      <p><b>Project backup</b></p>
      <p>It is a copy of SMBstack's configuration intended for the administrator. It is stored in <code>/etc/bak/smbstack</code>, includes a timestamp in its name and up to three copies are kept.</p>
      <p>Only <code>smbbk.sh</code> creates project backups. <code>smbsetup.sh --update</code> runs <code>smbbk.sh</code> before overwriting the application code, instead of keeping a copy of its own.</p>
      <p><b>Routine-operation backup</b></p>
      <p>It is the copy a script takes of one specific file right before modifying it, to allow the change to be undone. It is stored next to the original file with the <code>.bak</code> suffix, and only one copy is kept, overwritten on every run.</p>
      <p>Some examples are <code>smb.conf.bak</code>, <code>ports.conf.bak</code> and <code>smbd.service.bak</code>.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>Este proyecto utiliza dos tipos de respaldo, con propósitos y reglas diferentes.</p>
      <p><b>Respaldo de proyecto</b></p>
      <p>Es una copia de la configuración de SMBstack destinada al administrador. Se almacena en <code>/etc/bak/smbstack</code>, incluye una marca de tiempo en el nombre y se conservan hasta tres copias.</p>
      <p>Solo <code>smbbk.sh</code> genera respaldos de proyecto. <code>smbsetup.sh --update</code> ejecuta <code>smbbk.sh</code> antes de sobrescribir el código de la aplicación, en lugar de mantener una copia propia.</p>
      <p><b>Respaldo de operación rutinaria</b></p>
      <p>Es una copia que un script realiza de un archivo concreto justo antes de modificarlo, para permitir deshacer el cambio. Se almacena junto al archivo original con el sufijo <code>.bak</code> y solo se conserva una copia, que se sobrescribe en cada ejecución.</p>
      <p>Algunos ejemplos son <code>smb.conf.bak</code>, <code>ports.conf.bak</code> y <code>smbd.service.bak</code>.</p>
    </td>
  </tr>
</table>

### NetBIOS

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <p>NetBIOS is a legacy protocol with security limitations, among them unauthenticated name resolution and exposure to spoofing and name poisoning attacks, such as NBT-NS poisoning.</p>
      <p>For this reason, NetBIOS remains disabled by default through <code>disable netbios = yes</code> in <code>smb.conf</code>, and the installer offers no option to enable it.</p>
      <p>Environments that need compatibility with legacy Windows clients must enable NetBIOS manually after the installation.</p>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <p>NetBIOS es un protocolo legado que presenta limitaciones de seguridad, entre ellas la resolución de nombres sin autenticación y la exposición a ataques de suplantación y envenenamiento de nombres, como NBT-NS poisoning.</p>
      <p>Por este motivo, NetBIOS permanece deshabilitado de forma predeterminada mediante <code>disable netbios = yes</code> en <code>smb.conf</code>, y el instalador no ofrece ninguna opción para activarlo.</p>
      <p>Los entornos que necesiten compatibilidad con clientes Windows antiguos deben habilitar NetBIOS manualmente después de la instalación.</p>
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

## ⚠️ WARNING: NETWORK ACCESS

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This project is designed for use on a local network (LAN). It does not include the security hardening needed for direct exposure to the internet. If internet access is required, an on-demand tunnel is recommended instead of opening ports directly. This enables access when needed without leaving the server permanently exposed.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este proyecto está diseñado para usarse en una red local (LAN). No cuenta con las medidas de seguridad necesarias para exponerlo directamente a Internet. Si se requiere acceso desde Internet, se recomienda utilizar un túnel bajo demanda en lugar de abrir puertos directamente. Así, el acceso se habilita cuando hace falta y el servidor no queda expuesto permanentemente.
    </td>
  </tr>
</table>

> **CSRF protection.** `web/smbshared.php` has no login by design. Guest access for the whole LAN, and for the tunnel when it is enabled, is intentional.
>
> What it does have is a per-session token on the four forms that change state: upload, new folder, new file and recycle. A POST is accepted only if the page was actually loaded first.
>
> This blocks a malicious site from silently auto-submitting a form to your server through a visitor's browser. It does not restrict who can use the browser itself: that is still governed by network reachability, LAN or tunnel.
>
> **Protección CSRF.** `web/smbshared.php` no tiene login por diseño. El acceso de invitado para toda la LAN, y para el túnel cuando está activo, es intencional.
>
> Lo que sí tiene es un token por sesión en los cuatro formularios que modifican estado: subir, nueva carpeta, nuevo archivo y papelera. Un POST se acepta solo si la página se cargó antes.
>
> Esto impide que un sitio malicioso envíe en silencio un formulario a su servidor a través del navegador de un visitante. No restringe quién puede usar el navegador: eso lo sigue gobernando el alcance de red, LAN o túnel.

> **Folder size display.** The total size shown for the folder being browsed in `web/smbshared.php` is cached for 30 seconds per path, to avoid re-walking a potentially large subtree on every page load.
>
> The number can therefore lag up to 30 seconds behind the real content. That is purely cosmetic: quota enforcement is handled independently by `smbwatch.sh` and its own size checks, not by this displayed value.
>
> **Tamaño de carpeta mostrado.** El tamaño total que se muestra para la carpeta que se está navegando en `web/smbshared.php` se cachea 30 segundos por ruta, para evitar recorrer un subárbol potencialmente grande en cada carga de página.
>
> Por eso el número puede quedar hasta 30 segundos desactualizado respecto al contenido real. Es puramente cosmético: el cumplimiento de la cuota lo maneja de forma independiente `smbwatch.sh` con sus propios chequeos de tamaño, no este valor mostrado.

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
|Scripts, Binaries, Infrastructure|[![GPL-3.0](https://img.shields.io/badge/Open_Core-GPLv3-blue.svg?style=for-the-badge&labelWidth=120&logoWidth=20)](LICENSE)|
|RAG, Workers, Specialized Modules, Docs|[![CC](https://img.shields.io/badge/Core_Engine-CC_BY--NC--ND_4.0-lightgrey.svg?style=for-the-badge&labelWidth=120&logoWidth=20)](docs/LICENSE-CC-BY-NC-ND-4.0.md)|

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
