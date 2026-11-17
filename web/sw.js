// GPS Land Measure - Production Offline Service Worker (PWA)
const CACHE_NAME = 'gps-land-measure-v4';

const CORE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png'
];

// Install: Cache critical app shell assets
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(CORE_ASSETS).catch((err) => {
        console.warn('Pre-cache warning:', err);
      });
    })
  );
});

// Activate: Claim clients and purge outdated caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('Purging old cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: Never block external map tiles! Cache app shell for offline
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // 1. External Map Tiles & APIs: Let the browser handle directly with native cache!
  if (url.origin !== self.location.origin) {
    return; // Pass through to native browser network
  }

  // 2. Local App Shell & Assets (Network-First with Offline Cache Fallback)
  event.respondWith(
    fetch(request).then((networkResponse) => {
      if (networkResponse && networkResponse.status === 200) {
        const responseToCache = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(request, responseToCache);
        });
      }
      return networkResponse;
    }).catch(() => {
      return caches.match(request).then((cachedResponse) => {
        if (cachedResponse) return cachedResponse;
        if (request.mode === 'navigate') {
          return caches.match('./index.html') || caches.match('index.html');
        }
        return new Response('Offline', { status: 503 });
      });
    })
  );
});
