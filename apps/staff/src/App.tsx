import { useEffect, useState } from 'react';
import { ORDER_STATUS_LABELS, nextStatus } from '@duby/shared';
import { APP_VERSION } from './version.js';
import { isConfigured, supabase } from './supabase.js';

type Health = 'checking' | 'connected' | 'unreachable' | 'unconfigured';

/**
 * شاشة المرحلة صفر: تثبت أن خط النشر يعمل من طرف إلى طرف.
 * تُستبدل بهيكل التطبيق في المرحلة الأولى.
 */
export function App() {
  const [health, setHealth] = useState<Health>(isConfigured ? 'checking' : 'unconfigured');

  useEffect(() => {
    if (!supabase) return;
    let cancelled = false;

    /*
     * اتصال حقيقي بقاعدة البيانات عبر دالة صحة عامة. لا نقرأ جدولًا هنا لأن
     * anon لا يملك وصولًا إلى أي جدول — وهذا هو المطلوب.
     */
    void (async () => {
      try {
        const { error } = await supabase.rpc('health_check');
        if (!cancelled) setHealth(error ? 'unreachable' : 'connected');
      } catch {
        if (!cancelled) setHealth('unreachable');
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="brand">دوبي</span>
        <span className="subtitle">لوحة الموظفين</span>
      </header>

      <main className="app-content">
        <h1>مرحبًا يا دوبي</h1>
        <p className="lede">
          خط النشر يعمل. هذه الشاشة مؤقتة وتُستبدل بهيكل التطبيق في المرحلة الأولى.
        </p>

        <dl className="facts">
          <dt>الإصدار</dt>
          <dd>{APP_VERSION}</dd>

          <dt>قاعدة البيانات</dt>
          <dd data-health={health}>{healthLabel(health)}</dd>

          <dt>المسار التالي من «مؤكد»</dt>
          <dd>{ORDER_STATUS_LABELS[nextStatus('confirmed')!.to]}</dd>
        </dl>
      </main>

      <nav className="app-nav">
        <span>الطلبات</span>
        <span>العملاء</span>
        <span>الصندوق</span>
        <span>المزيد</span>
      </nav>
    </div>
  );
}

function healthLabel(health: Health): string {
  switch (health) {
    case 'checking':
      return 'جارٍ الفحص…';
    case 'connected':
      return 'متصلة';
    case 'unreachable':
      return 'غير متاحة';
    case 'unconfigured':
      return 'غير مهيّأة';
  }
}
