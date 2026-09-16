import { useEffect, useState } from 'react';
import { atLeast, errorText, type StaffRole } from '@duby/shared';
import { supabase } from '../supabase.js';
import { callRpc } from '../lib/api.js';

type Property = {
  id: string;
  code: string;
  name: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  is_active: boolean;
};

export function Properties({ role }: { role: StaffRole }) {
  const [rows, setRows] = useState<Property[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  const canEdit = atLeast(role, 'manager');

  async function load() {
    if (!supabase) return;
    const { data, error: loadError } = await supabase
      .from('properties')
      .select('id, code, name, address, latitude, longitude, is_active')
      .is('deleted_at', null)
      .order('code');

    if (loadError) setError('تعذّر تحميل العقارات');
    else setRows((data ?? []) as Property[]);
  }

  useEffect(() => {
    void load();
  }, []);

  async function toggleActive(property: Property) {
    const result = await callRpc('fn_set_property_active', {
      p_id: property.id,
      p_active: !property.is_active,
    });

    if (!result.ok) setError(errorText(result.code));
    else await load();
  }

  return (
    <section>
      <header className="screen-header">
        <h2>العقارات</h2>
        {canEdit && (
          <button type="button" onClick={() => setAdding((value) => !value)}>
            {adding ? 'إغلاق' : 'إضافة عقار'}
          </button>
        )}
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {adding && (
        <PropertyForm
          onDone={async () => {
            setAdding(false);
            await load();
          }}
          onError={setError}
        />
      )}

      {rows.length === 0 ? (
        <p className="empty">لا توجد عقارات بعد.</p>
      ) : (
        <ul className="cards">
          {rows.map((property) => (
            <li key={property.id} className="card">
              <div className="card-main">
                <strong>{property.name}</strong>
                <span className="muted">{property.code}</span>
                {property.address && <span className="muted">{property.address}</span>}
              </div>

              <div className="card-actions">
                {property.latitude !== null && property.longitude !== null && (
                  <a
                    href={`https://www.google.com/maps?q=${property.latitude},${property.longitude}`}
                    target="_blank"
                    rel="noreferrer noopener"
                  >
                    الموقع
                  </a>
                )}

                <span className={property.is_active ? 'badge-on' : 'badge-off'}>
                  {property.is_active ? 'فعّال' : 'موقوف'}
                </span>

                {canEdit && (
                  <button type="button" onClick={() => void toggleActive(property)}>
                    {property.is_active ? 'إيقاف' : 'تفعيل'}
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function PropertyForm({
  onDone,
  onError,
}: {
  onDone: () => Promise<void>;
  onError: (message: string) => void;
}) {
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');
  const [coords, setCoords] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);

    // الإحداثيات تُلصق من خرائط Google بصيغة "23.588, 58.3829"
    const [latitude, longitude] = coords
      .split(',')
      .map((part) => Number(part.trim()))
      .filter((value) => Number.isFinite(value));

    const result = await callRpc('fn_upsert_property', {
      p_id: null,
      p_code: code,
      p_name: name,
      p_address: address || null,
      p_latitude: latitude ?? null,
      p_longitude: longitude ?? null,
    });

    setBusy(false);

    if (!result.ok) onError(result.message ?? errorText(result.code));
    else await onDone();
  }

  return (
    <div className="form">
      <label htmlFor="code">الرمز</label>
      <input
        id="code"
        value={code}
        onChange={(e) => setCode(e.target.value.toUpperCase())}
        placeholder="BRJ1"
        maxLength={16}
      />

      <label htmlFor="name">الاسم</label>
      <input id="name" value={name} onChange={(e) => setName(e.target.value)} />

      <label htmlFor="address">العنوان</label>
      <input id="address" value={address} onChange={(e) => setAddress(e.target.value)} />

      <label htmlFor="coords">الإحداثيات</label>
      <input
        id="coords"
        value={coords}
        onChange={(e) => setCoords(e.target.value)}
        placeholder="23.588, 58.3829"
        inputMode="decimal"
      />

      <button type="button" onClick={() => void submit()} disabled={busy || !code || !name}>
        {busy ? 'جارٍ الحفظ…' : 'حفظ'}
      </button>
    </div>
  );
}
