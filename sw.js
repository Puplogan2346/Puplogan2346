// Service worker for offline support.
// Bump CACHE_VERSION whenever the cached assets change to invalidate old caches.
const CACHE_VERSION = "workday-checklist-v2";
const ASSETS = [
  "./", "./index.html", "./manifest.json", "./icon.svg",
  "./assets/app.css", "./assets/config.js", "./assets/supabase.js",
  "./assets/store.js", "./assets/history.js", "./assets/auth.js", "./assets/app.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Cache-first for our own assets, falling back to network.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request)
        .then((res) => {
          // Cache same-origin successful responses for future offline use.
          if (res.ok && new URL(event.request.url).origin === self.location.origin) {
            const copy = res.clone();
            caches.open(CACHE_VERSION).then((cache) => cache.put(event.request, copy));
          }
          return res;
        })
        .catch(() => cached);
    })
  );
});
