import { useState, type FormEvent } from 'react';
import { normalizeOmaniPhone } from '@duby/shared';
import { callApi } from '../lib/api.js';

/**
 * استكمال بيانات العميل الجديد.
 *
 * لا حقل للعقار ولا قائمة عقارات: تسمية العقار داخلية للتمييز التشغيلي،
 * والعميل لا يراها. الخادم يقرأ العقار من سجل العميل ولا يقبله من هنا.
 */
export function ProfileStep({
  scanSessionId,
  onDone,
}: {
  scanSessionId: string;
  onDone: () => void;
}) {
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [floor, setFloor] = useState('');
  const [apartment, setApartment] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();

    if (!normalizeOmaniPhone(phone)) {
      setError('رقم الهاتف غير صحيح. أدخل ٨ أرقام تبدأ بـ ٧ أو ٩.');
      return;
    }

    setBusy(true);
    setError(null);

    const result = await callApi('/complete-profile', {
      scan_session_id: scanSessionId,
      full_name: fullName,
      phone,
      floor_number: floor,
      apartment_number: apartment,
    });

    setBusy(false);

    if (!result.ok) setError(`${result.message} (${result.requestId.slice(0, 6)})`);
    else onDone();
  }

  return (
    <form onSubmit={submit} className="step">
      <h1>أهلًا بك</h1>
      <p>أكمل بياناتك مرة واحدة، ثم اطلب الخدمة متى شئت.</p>

      <label htmlFor="full-name">الاسم الكامل</label>
      <input
        id="full-name"
        value={fullName}
        onChange={(e) => setFullName(e.target.value)}
        autoComplete="name"
        required
        minLength={2}
      />

      <label htmlFor="phone">رقم الهاتف</label>
      <input
        id="phone"
        value={phone}
        onChange={(e) => setPhone(e.target.value)}
        inputMode="numeric"
        autoComplete="tel"
        placeholder="9XXXXXXX"
        required
      />

      <div className="row">
        <div>
          <label htmlFor="floor">الطابق</label>
          <input
            id="floor"
            value={floor}
            onChange={(e) => setFloor(e.target.value)}
            inputMode="numeric"
            required
          />
        </div>
        <div>
          <label htmlFor="apartment">رقم الشقة</label>
          <input
            id="apartment"
            value={apartment}
            onChange={(e) => setApartment(e.target.value)}
            inputMode="numeric"
            required
          />
        </div>
      </div>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <button type="submit" disabled={busy}>
        {busy ? 'جارٍ الحفظ…' : 'متابعة'}
      </button>
    </form>
  );
}
