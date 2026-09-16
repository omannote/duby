import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  /*
   * ملف بيئة واحد في جذر المستودع بدل واحد لكل تطبيق: القيم نفسها تخدم
   * التطبيقين، ونسخة ثانية تعني نسختين تتباعدان. README يقول
   * `cp .env.example .env.local` في الجذر، وبدون هذا السطر لا يقرأه vite.
   */
  envDir: fileURLToPath(new URL('../..', import.meta.url)),

  // مسارات العودة من الدفع تُخدَم من نفس الصفحة
  preview: { port: 4174 },
  appType: 'spa',
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
