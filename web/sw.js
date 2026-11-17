// GPS Land Measure - Production Offline Service Worker (PWA)
const CACHE_NAME = 'gps-land-measure-v6';
const TILE_CACHE_NAME = 'gps-map-tiles-v1';

const CORE_ASSETS = [
  './',
  'index.html',
  'flutter_bootstrap.js',
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
      return Promise.all(
        CORE_ASSETS.map((asset) => {
          return cache.add(asset).catch((err) => {
            console.log('Optional asset not yet available during pre-cache:', asset);
          });
        })
      );
    })
  );
});

// Activate: Claim clients and purge outdated caches (preserve map tile cache!)
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

// Fetch: 100% Offline Capability for App Shell, Fonts, and Map Tiles!
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // 1. External Map Tiles (Google Satellite, OSM, ArcGIS)
  const isMapTile = url.hostname.includes('google.com') ||
                    url.hostname.includes('openstreetmap.org') ||
                    url.hostname.includes('arcgisonline.com');

  if (isMapTile) {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          if (networkResponse && (networkResponse.status === 200 || networkResponse.type === 'opaque')) {
            const clone = networkResponse.clone();
            caches.open(TILE_CACHE_NAME).then((cache) => {
              cache.put(request, clone).catch(() => {});
            });
          }
          return networkResponse;
        })
        .catch(() => {
          // When offline in the field: serve cached tile from tile cache!
          return caches.open(TILE_CACHE_NAME).then((cache) => {
            return cache.match(request, { ignoreSearch: true });
          });
        })
    );
    return;
  }

  // 2. Google Fonts & Stylesheets (Cache offline for Khmer typography)
  if (url.hostname.includes('fonts.googleapis.com') || url.hostname.includes('fonts.gstatic.com')) {
    event.respondWith(
      caches.open(CACHE_NAME).then((cache) => {
        return cache.match(request).then((cachedResponse) => {
          if (cachedResponse) return cachedResponse;
          return fetch(request)
            .then((networkResponse) => {
              if (networkResponse && networkResponse.status === 200) {
                cache.put(request, networkResponse.clone());
              }
              return networkResponse;
            })
            .catch(() => cachedResponse);
        });
      })
    );
    return;
  }

  // 3. Ignore non-origin external requests (analytics, 3rd party scripts)
  if (url.origin !== self.location.origin) {
    return;
  }

  // 4. Local App Shell & JavaScript/WASM Engine (Network-First with Offline Cache Fallback)
  event.respondWith(
    caches.open(CACHE_NAME).then((cache) => {
      return fetch(request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            cache.put(request, networkResponse.clone());
          }
          return networkResponse;
        })
        .catch(() => {
          // Serve from cache even if query string differs (?v=...)
          return cache.match(request, { ignoreSearch: true }).then((cachedResponse) => {
            if (cachedResponse) return cachedResponse;
            if (request.mode === 'navigate') {
              return cache.match('index.html', { ignoreSearch: true }) || cache.match('./', { ignoreSearch: true });
            }
            return new Response('Offline', { status: 503 });
          });
        });
    })
  );
});
