/// <reference lib="webworker" />
import { clientsClaim } from 'workbox-core';
import { NetworkOnly, StaleWhileRevalidate } from 'workbox-strategies';
import { precacheAndRoute } from 'workbox-precaching';
import { registerRoute } from 'workbox-routing';

declare const self: ServiceWorkerGlobalScope;

/*
 * أصول التطبيق فقط، ببصمة إصدار في كل اسم — فلا تتعارض نسختان.
 */
precacheAndRoute(self.__WB_MANIFEST);

/*
 * Supabase لا يُعترض إطلاقًا.
 *
 * في النظام السابق كان Service Worker يعترض طلبات Supabase، فخزّن بيانات
 * عملاء في كاش المتصفح، وقدّم نسخة قديمة أثناء التشخيص فأضاع عدة جولات
 * على كود لم يكن يعمل أصلًا على الجهاز.
 */
registerRoute(({ url }) => url.hostname.endsWith('.supabase.co'), new NetworkOnly());

// الخطوط المُستضافة ذاتيًا وحدها
registerRoute(({ request }) => request.destination === 'font', new StaleWhileRevalidate());

self.addEventListener('message', (event) => {
  if ((event.data as { type?: string } | null)?.type === 'SKIP_WAITING') {
    void self.skipWaiting();
  }
});

clientsClaim();
