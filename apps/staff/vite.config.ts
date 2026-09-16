import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

/*
 * ملفات منفصلة لا حزمة مضمّنة — هذا ما يسمح بـ CSP صارم بلا 'unsafe-inline'.
 * النظام السابق كان ملفًا واحدًا فاضطر إلى السماح بالسكربت المضمّن.
 */
export default defineConfig({
  /*
   * ملف بيئة واحد في جذر المستودع بدل واحد لكل تطبيق: القيم نفسها تخدم
   * التطبيقين، ونسخة ثانية تعني نسختين تتباعدان. README يقول
   * `cp .env.example .env.local` في الجذر، وبدون هذا السطر لا يقرأه vite.
   */
  envDir: fileURLToPath(new URL('../..', import.meta.url)),

  plugins: [
    react(),
    VitePWA({
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'prompt', // لا تحديث صامت: الموظف يعرف أن نسخته تغيّرت
      injectManifest: { globPatterns: ['**/*.{js,css,html,woff2}'] },
      manifest: {
        name: 'دوبي — لوحة الموظفين',
        short_name: 'دوبي',
        lang: 'ar',
        dir: 'rtl',
        start_url: '/',
        display: 'standalone',
        background_color: '#F7F8F7',
        theme_color: '#0F3D2E',
        icons: [],
      },
    }),
  ],
  build: {
    target: 'es2022',
    assetsInlineLimit: 0,

    /*
     * 'hidden' يولّد الخرائط بلا تعليق sourceMappingURL، فلا يطلبها المتصفح.
     * الخرائط تُرفع كأثر في CI وتُحذف من dist قبل النشر — فهي تكشف المصدر
     * كاملًا لتطبيق يتعامل مع بيانات عملاء.
     */
    sourcemap: 'hidden',
  },
});
