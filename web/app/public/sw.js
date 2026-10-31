// Murmur's service worker: keeps the model weights the browser downloads from Hugging Face, so they
// survive reloads and the app works offline. It caches nothing else and sends nothing anywhere.
//
// Voz caches its own bundle (desert-ant-voz-<revision>), so its requests pass through untouched.
// A new version of this file drops caches it no longer knows, including old Voz revisions.

const MODEL_CACHE = "murmur-models";
const KEEP = [MODEL_CACHE, "desert-ant-voz-v0.5.0"];
const HOSTS = /(^|\.)huggingface\.co$|(^|\.)hf\.co$/;

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if ((name.startsWith("murmur-") || name.startsWith("desert-ant-")) && !KEEP.includes(name)) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || !HOSTS.test(url.hostname) || url.pathname.includes("/desert-ant-labs/voz/")) return;
  // Weights are addressed by revision, so a cached response never goes stale.
  if (!url.pathname.includes("/resolve/")) return;
  event.respondWith((async () => {
    const cache = await caches.open(MODEL_CACHE);
    const hit = await cache.match(event.request);
    if (hit) return hit;
    const response = await fetch(event.request);
    if (response.ok) await cache.put(event.request, response.clone());
    return response;
  })());
});
