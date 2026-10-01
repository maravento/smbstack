<?php
// maravento.com
//
////////////////////////////////////////////////////////////////////////////////
//
// index.php
// smbstack - Main Container
// https://github.com/maravento/smbstack
//
////////////////////////////////////////////////////////////////////////////////

// $tab must always be validated against $allowed_tabs before being echoed into
// the href/class attributes below; any new tab value added here must also be
// added to $allowed_tabs.
$tab = isset($_GET['tab']) ? $_GET['tab'] : 'shared';
$allowed_tabs = ['shared', 'audit', 'report'];
if (!in_array($tab, $allowed_tabs)) $tab = 'shared';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <script>
        try { if (localStorage.getItem('smbstack_theme') === 'dark') { document.documentElement.classList.add('dark'); } } catch (e) {}
    </script>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SMBstack</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🗂️</text></svg>" type="image/svg+xml">
    <link rel="manifest" href="/manifest.json">
    <link rel="apple-touch-icon" href="/icon.svg">
    <meta name="theme-color" content="#2c3e50">
    <style>
        :root {
            /* Typography scale */
            --fs-xxs: 0.75rem;
            --fs-xs: 0.8rem;
            --fs-sm: 0.85rem;
            --fs-base: 0.9rem;
            --fs-md: 0.95rem;
            --fs-lg: 1rem;
            --fs-xl: 1.1rem;
            --fs-icon: 1.3rem;
            /* Spacing scale */
            --sp-1: 0.25rem;
            --sp-2: 0.5rem;
            --sp-3: 0.75rem;
            --sp-4: 1rem;
            --sp-5: 1.25rem;
            --sp-6: 1.5rem;
            --sp-8: 2rem;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        html, body {
            height: 100%;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Ubuntu, sans-serif;
            background: #1a2332;
            overflow: hidden;
            transition: background .2s;
        }

        html.dark { background: #0b0f16; }
        html.dark .header { background: #141721; }
        html.dark .header-top { border-bottom-color: rgba(255,255,255,0.05); }
        html.dark .header-date { background: rgba(255,255,255,0.05); color: #e2e8f0; }
        html.dark .tabs { background: #0f1117; }
        html.dark .tab { color: #607d8b; }
        html.dark .tab:hover { color: #cbd5e0; background: rgba(255,255,255,0.03); }
        html.dark .tab.active { background: rgba(246,173,85,0.06); }
        html.dark .btn-theme { background: #232838; color: #e2e8f0; }
        html.dark .btn-theme:hover { background: #2d3748; }

        .btn-theme {
            background: rgba(255,255,255,0.08);
            color: #e6eef8;
            border: none;
            padding: var(--sp-1) var(--sp-2);
            border-radius: 6px;
            font-size: var(--fs-sm);
            cursor: pointer;
            transition: background .15s;
        }
        .btn-theme:hover { background: rgba(255,255,255,0.15); }

        /* ── HEADER ── */
        .header {
            background: #2c3e50;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
            display: flex;
            flex-direction: column;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 100;
        }

        .header-top {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: var(--sp-2) var(--sp-5);
            border-bottom: 1px solid rgba(255,255,255,0.08);
        }

        .header-right {
            display: flex;
            align-items: center;
            gap: var(--sp-2);
        }

        .header-brand {
            display: flex;
            align-items: center;
            gap: var(--sp-2);
            color: white;
            font-size: var(--fs-lg);
            font-weight: 700;
            letter-spacing: 0.02em;
            text-decoration: none;
        }

        .header-brand:hover {
            color: white;
            text-decoration: underline;
        }

        .header-brand span {
            font-size: var(--fs-icon);
        }

        .header-title {
            color: #e2e8f0;
            font-size: var(--fs-md);
            font-weight: 600;
        }

        .header-date {
            color: #e2e8f0;
            font-size: var(--fs-sm);
            font-weight: 600;
            background: rgba(255,255,255,0.07);
            padding: var(--sp-1) var(--sp-3);
            border-radius: 6px;
        }

        /* ── TABS ── */
        .tabs {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0 var(--sp-4);
            gap: var(--sp-1);
            background: #243447;
        }

        .tab {
            display: flex;
            align-items: center;
            gap: var(--sp-2);
            padding: var(--sp-2) var(--sp-4);
            font-size: var(--fs-sm);
            font-weight: 500;
            color: #8899aa;
            text-decoration: none;
            border-bottom: 3px solid transparent;
            transition: color 0.15s, border-color 0.15s, background 0.15s;
            cursor: pointer;
            white-space: nowrap;
            border-radius: 6px 6px 0 0;
            margin-bottom: -1px;
        }

        .tab:hover {
            color: #cbd5e0;
            background: rgba(255,255,255,0.05);
        }

        .tab.active {
            color: #ffffff;
            border-bottom-color: #f6ad55;
            background: rgba(246,173,85,0.08);
        }

        .tab-icon { font-size: var(--fs-lg); }

        /* ── IFRAME ── */
        .frame-container {
            position: fixed;
            top: 88px;
            left: 0;
            right: 0;
            bottom: 0;
        }

        iframe {
            width: 100%;
            height: 100%;
            border: none;
            background: transparent;
        }
    </style>
</head>
<body>

<div class="header">
    <div class="header-top">
        <a class="header-brand" href="https://github.com/maravento/smbstack" target="_blank" rel="noopener noreferrer">
            <span>🗂️</span> SMBstack
        </a>
        <div class="header-title">Shared Folder &amp; Audit</div>
        <div class="header-right">
            <button class="btn-theme" id="btnTheme" onclick="toggleTheme()" title="Toggle dark/light mode">🌙</button>
            <div class="header-date" id="clock"></div>
        </div>
    </div>
    <div class="tabs">
        <a class="tab <?= $tab === 'shared' ? 'active' : '' ?>" href="?tab=shared" <?= $tab === 'shared' ? 'aria-current="page"' : '' ?>>
            <span class="tab-icon">📁</span> Shared
        </a>
        <a class="tab <?= $tab === 'audit' ? 'active' : '' ?>" href="?tab=audit" <?= $tab === 'audit' ? 'aria-current="page"' : '' ?>>
            <span class="tab-icon">📊</span> Audit
        </a>
        <a class="tab <?= $tab === 'report' ? 'active' : '' ?>" href="?tab=report" <?= $tab === 'report' ? 'aria-current="page"' : '' ?>>
            <span class="tab-icon">💾</span> Report
        </a>
    </div>
</div>

<div class="frame-container">
    <?php if ($tab === 'shared'): ?>
        <iframe src="/shared/" id="frame-shared" onload="syncFrameTheme(this)"></iframe>
    <?php elseif ($tab === 'report'): ?>
        <iframe src="/report/" id="frame-report" onload="syncFrameTheme(this)"></iframe>
    <?php else: ?>
        <iframe src="/audit/" id="frame-audit" onload="syncFrameTheme(this)"></iframe>
    <?php endif; ?>
</div>

<script>
    function updateClock() {
        const now = new Date();
        document.getElementById('clock').textContent =
            now.toISOString().replace('T', ' ').substring(0, 19);
    }
    updateClock();
    setInterval(updateClock, 1000);

    function broadcastTheme(dark) {
        ['frame-shared', 'frame-audit', 'frame-report'].forEach(function(id) {
            var f = document.getElementById(id);
            if (f && f.contentWindow) {
                f.contentWindow.postMessage({ smbstackTheme: dark ? 'dark' : 'light' }, window.location.origin);
            }
        });
    }

    function toggleTheme() {
        var dark = document.documentElement.classList.toggle('dark');
        document.getElementById('btnTheme').textContent = dark ? '☀️' : '🌙';
        try { localStorage.setItem('smbstack_theme', dark ? 'dark' : 'light'); } catch (e) {}
        broadcastTheme(dark);
    }

    function syncFrameTheme(iframe) {
        var dark = document.documentElement.classList.contains('dark');
        if (iframe && iframe.contentWindow) {
            iframe.contentWindow.postMessage({ smbstackTheme: dark ? 'dark' : 'light' }, window.location.origin);
        }
    }

    function initTheme() {
        if (document.documentElement.classList.contains('dark')) {
            document.getElementById('btnTheme').textContent = '☀️';
        }
    }
    initTheme();

    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/sw.js').catch(function() {});
    }
</script>

</body>
</html>
