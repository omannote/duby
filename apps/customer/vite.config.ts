import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
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
