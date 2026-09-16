import { normalizeQrToken } from '@duby/shared';

const APP_VERSION = import.meta.env.VITE_APP_VERSION ?? 'dev';

/**
 * شاشة المرحلة صفر لصفحة العميل.
 * تقرأ الرمز من الرابط وتثبت أن التطبيق يُبنى ويُنشر — بلا أي نداء بيانات بعد.
 */
export function App() {
  const token = normalizeQrToken(window.location.href);

  return (
    <div className="page">
      <header>
        <span className="brand">دوبي</span>
        <span className="tagline">للغسيل السريع والجاف</span>
      </header>

      <main>
        <h1>مرحبًا يا دوبي</h1>
        <p>صفحة طلب الغسيل قيد الإنشاء. ستكون جاهزة في المرحلة الثانية.</p>
        <p className="token">{token ? 'تم التعرّف على الرمز' : 'لا يوجد رمز في الرابط'}</p>
      </main>

      <footer>الإصدار {APP_VERSION}</footer>
    </div>
  );
}
