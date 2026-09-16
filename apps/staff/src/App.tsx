import { useEffect, useState } from 'react';
import { ROLE_LABELS } from '@duby/shared';
import { APP_VERSION } from './version.js';
import { isConfigured } from './supabase.js';
import { signOut, useStaffSession } from './lib/session.js';
import { watchForUpdates } from './lib/update-prompt.js';
import { SignIn } from './screens/SignIn.js';
import { Properties } from './screens/Properties.js';
import { Customers } from './screens/Customers.js';
import { Orders } from './screens/Orders.js';
import { Cash } from './screens/Cash.js';
import { NotificationSettings } from './screens/NotificationSettings.js';

type Tab = 'orders' | 'cash' | 'customers' | 'properties' | 'notifications' | 'more';

export function App() {
  const session = useStaffSession();
  const [tab, setTab] = useState<Tab>('orders');
  const [applyUpdate, setApplyUpdate] = useState<(() => void) | null>(null);

  // التحديث معلن لا صامت: الموظف يعرف أن نسخته تغيّرت
  useEffect(() => {
    watchForUpdates((apply) => setApplyUpdate(() => apply));
  }, []);

  if (!isConfigured) {
    return <Notice title="التطبيق غير مهيّأ" body="لم تُضبط بيانات الاتصال بقاعدة البيانات." />;
  }

  if (session.status === 'loading') {
    return <Notice title="جارٍ التحميل…" body="" />;
  }

  if (session.status === 'signed-out') {
    return <SignIn />;
  }

  /*
   * حساب دخول بلا سجل موظف فعّال — أو موظف عُطّل بعد دخوله. auth_role() تعيد
   * null فلا يقرأ شيئًا؛ نوضح السبب بدل ترك شاشة فارغة.
   */
  if (session.status === 'no-profile') {
    return (
      <Notice
        title="لا يوجد حساب موظف فعّال"
        body="هذا الحساب غير مرتبط بموظف فعّال. راجع مدير النظام."
        onSignOut={() => void signOut()}
      />
    );
  }

  const { staff } = session;

  return (
    <div className="app-shell">
      {applyUpdate && (
        <div className="update-bar" role="status">
          <span>يتوفر إصدار جديد</span>
          <button type="button" onClick={applyUpdate}>
            تحديث
          </button>
        </div>
      )}

      <header className="app-header">
        <div>
          <span className="brand">دوبي</span>
          <span className="subtitle">{ROLE_LABELS[staff.role]}</span>
        </div>
        <span className="staff-name">{staff.fullName}</span>
      </header>

      <main className="app-content">
        {tab === 'orders' && <Orders staffId={staff.staffId} />}
        {tab === 'cash' && <Cash role={staff.role} staffId={staff.staffId} />}
        {tab === 'customers' && <Customers role={staff.role} />}
        {tab === 'properties' && <Properties role={staff.role} />}
        {tab === 'notifications' && <NotificationSettings role={staff.role} />}
        {tab === 'more' && (
          <section>
            <header className="screen-header">
              <h2>المزيد</h2>
            </header>
            <button type="button" className="ghost wide" onClick={() => setTab('notifications')}>
              إشعارات الحالات
            </button>

            <button type="button" className="ghost wide" onClick={() => setTab('properties')}>
              العقارات
            </button>

            <dl className="facts">
              <dt>الموظف</dt>
              <dd>{staff.fullName}</dd>
              <dt>الدور</dt>
              <dd>{ROLE_LABELS[staff.role]}</dd>
              <dt>الإصدار</dt>
              <dd>{APP_VERSION}</dd>
            </dl>
            {/* زر خروج ظاهر دائمًا — كان مفقودًا في النظام السابق */}
            <button type="button" className="danger" onClick={() => void signOut()}>
              تسجيل الخروج
            </button>
          </section>
        )}
      </main>

      <nav className="app-nav no-print">
        <button type="button" data-active={tab === 'orders'} onClick={() => setTab('orders')}>
          الطلبات
        </button>
        <button type="button" data-active={tab === 'cash'} onClick={() => setTab('cash')}>
          الصندوق
        </button>
        <button type="button" data-active={tab === 'customers'} onClick={() => setTab('customers')}>
          العملاء
        </button>
        <button type="button" data-active={tab === 'more'} onClick={() => setTab('more')}>
          المزيد
        </button>
      </nav>
    </div>
  );
}

function Notice({
  title,
  body,
  onSignOut,
}: {
  title: string;
  body: string;
  onSignOut?: () => void;
}) {
  return (
    <div className="notice">
      <h1>{title}</h1>
      {body && <p>{body}</p>}
      {onSignOut && (
        <button type="button" onClick={onSignOut}>
          تسجيل الخروج
        </button>
      )}
    </div>
  );
}
