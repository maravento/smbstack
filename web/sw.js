// SMBstack - Service Worker
// Caches only the static app shell. Everything under /shared and /audit
// (folder listings, file downloads, audit log data) must always be fetched
// live so uploads, deletes, and audit entries are never served stale.

const CACHE = 'smbstack-shell-v1';
const SHELL = ['/', '/manifest.json', '/icon.svg'];

self.addEventListener('install', (event) => {
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
        )
    );
    self.clients.claim();
});

self.addEventListener('fetch', (event) => {
    const req = event.request;
    if (req.method !== 'GET') return;

    const url = new URL(req.url);
    if (url.pathname.startsWith('/shared') || url.pathname.startsWith('/audit')) {
        return;
    }

    event.respondWith(caches.match(req).then((cached) => cached || fetch(req)));
});
