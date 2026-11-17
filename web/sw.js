// GPS Land Measure - Production Offline Service Worker (PWA)
const CACHE_NAME = 'gps-land-measure-v3';
const TILE_CACHE_NAME = 'gps-map-tiles-v1';

const CORE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png'
];

// Install: Cache critical core assets
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(CORE_ASSETS).catch((err) => {
        console.warn('Some core assets failed to pre-cache:', err);
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
          if (key !== CACHE_NAME && key !== TILE_CACHE_NAME) {
            console.log('Purging old cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: Smart Network-First / Stale-While-Revalidate strategy for 100% offline usage
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // 1. Map Tiles (Google, OpenStreetMap, ArcGIS, Topo)
  if (
    url.hostname.includes('google.com') && url.pathname.includes('/vt/') ||
    url.hostname.includes('openstreetmap.org') ||
    url.hostname.includes('arcgisonline.com') ||
    url.hostname.includes('opentopomap.org')
  ) {
    event.respondWith(
      caches.open(TILE_CACHE_NAME).then((cache) => {
        return cache.match(request).then((cachedResponse) => {
          if (cachedResponse) {
            // Return cached tile immediately
            return cachedResponse;
          }
          // Fetch from network and cache
          return fetch(request).then((networkResponse) => {
            if (networkResponse && networkResponse.status === 200) {
              cache.put(request, networkResponse.clone());
            }
            return networkResponse;
          }).catch(() => {
            // When offline and tile not in cache, return null/fallback
            return new Response('', { status: 408, headers: { 'Content-Type': 'image/png' } });
          });
        });
      })
    );
    return;
  }

  // 2. Navigation & App Shell (index.html, JS bundles, canvaskit, fonts)
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
      // Offline fallback: Match from cache
      return caches.match(request).then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }
        // If requesting a page/navigation while offline, return cached index.html
        if (request.mode === 'navigate') {
          return caches.match('./index.html') || caches.match('index.html');
        }
        return new Response('Offline: Resource not available in cache.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain' }
        });
      });
    })
  );
});

