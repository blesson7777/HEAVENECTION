const CACHE_NAME = "heavenection-calltrack-v3";
const STATIC_ASSETS = [
    "/offline/",
    "/manifest.webmanifest",
    "/static/css/style.css",
    "/static/css/dashboard.css",
    "/static/css/heavenection-calltrack.css",
    "/static/js/dashboard-ux.js",
    "/static/js/heavenection-calltrack.js",
    "/static/js/heavenection-network.js",
    "/static/js/heavenection-pwa.js",
    "/static/pwa/icon-192.png",
    "/static/pwa/icon-512.png"
];

self.addEventListener("install", (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
    );
    self.skipWaiting();
});

self.addEventListener("activate", (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(
                keys
                    .filter((key) => key !== CACHE_NAME)
                    .map((key) => caches.delete(key))
            )
        )
    );
    self.clients.claim();
});

self.addEventListener("fetch", (event) => {
    if (event.request.method !== "GET") {
        return;
    }

    const requestUrl = new URL(event.request.url);
    const isSameOrigin = requestUrl.origin === self.location.origin;
    const isNavigationRequest = event.request.mode === "navigate";

    if (isSameOrigin && isNavigationRequest) {
        event.respondWith(
            fetch(event.request)
                .then((networkResponse) => {
                    const responseClone = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
                    return networkResponse;
                })
                .catch(async () => {
                    const cachedPage = await caches.match(event.request);
                    if (cachedPage) {
                        return cachedPage;
                    }
                    return caches.match("/offline/");
                })
        );
        return;
    }

    event.respondWith(
        caches.match(event.request).then((cachedResponse) => {
            if (cachedResponse) {
                return cachedResponse;
            }

            return fetch(event.request)
                .then((networkResponse) => {
                    if (!networkResponse || networkResponse.status !== 200 || event.request.url.startsWith("chrome-extension")) {
                        return networkResponse;
                    }
                    const responseClone = networkResponse.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
                    return networkResponse;
                })
                .catch(() => caches.match("/offline/"));
        })
    );
});
