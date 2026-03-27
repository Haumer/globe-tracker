const CACHE_NAME = "gt-v2";
const PRECACHE = ["/home", "/sources"];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);

  // Only cache same-origin GET requests
  if (e.request.method !== "GET" || url.origin !== location.origin) return;

  // Skip API, ActionCable, and auth routes
  if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/cable") || url.pathname.startsWith("/users/")) return;

  e.respondWith(
    fetch(e.request)
      .then((response) => {
        // Cache successful HTML and asset responses
        if (response.ok && (e.request.destination === "document" || e.request.destination === "style" || e.request.destination === "script")) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(e.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(e.request))
  );
});
