import { useEffect, useState } from 'react';
import { atLeast, errorText, type StaffRole } from '@duby/shared';
import { supabase } from '../supabase.js';
import { callRpc } from '../lib/api.js';
import { QrCard } from '../components/QrCard.js';

type Customer = {
  id: string;
  customer_no: number;
  full_name: string | null;
  phone: string | null;
  floor_number: string | null;
  apartment_number: string | null;
  profile_status: 'incomplete' | 'complete';
  is_active: boolean;
  properties: { id: string; name: string; code: string } | null;
  customer_qr_tokens: { token: string }[];
};

type PropertyOption = { id: string; name: string; code: string };

export function Customers({ role }: { role: StaffRole }) {
  const [rows, setRows] = useState<Customer[]>([]);
  const [properties, setProperties] = useState<PropertyOption[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [issued, setIssued] = useState<{ token: string; no: number; property: string } | null>(
    null,
  );

  const canDisable = atLeast(role, 'manager');

  async function load() {
    if (!supabase) return;

    const [customersResult, propertiesResult] = await Promise.all([
      supabase
        .from('customers')
        .select(
          'id, customer_no, full_name, phone, floor_number, apartment_number, profile_status, is_active, properties(id, name, code), customer_qr_tokens(token)',
        )
        .is('deleted_at', null)
        .order('customer_no', { ascending: false })
        .limit(200),
      supabase
        .from('properties')
        .select('id, name, code')
        .eq('is_active', true)
        .is('deleted_at', null)
        .order('code'),
    ]);

    if (customersResult.error) setError('تعذّر تحميل العملاء');
    else setRows((customersResult.data ?? []) as unknown as Customer[]);

    setProperties((propertiesResult.data ?? []) as PropertyOption[]);
  }

  useEffect(() => {
    void load();
  }, []);

  /*
   * اختيار العقار إلزامي وقت الإنشاء: تسمية العقار داخلية للتمييز التشغيلي
   * فقط، والعميل لا يراها ولا يختارها لاحقًا.
   */
  async function createCustomer(propertyId: string) {
    const result = await callRpc<{ customer: { customer_no: number }; qr_token: string }>(
      'fn_create_customer_with_qr',
      { p_property_id: propertyId },
    );

    if (!result.ok) {
      setError(errorText(result.code));
      return;
    }

    const property = properties.find((option) => option.id === propertyId);
    setIssued({
      token: result.data.qr_token,
      no: result.data.customer.customer_no,
      property: property?.name ?? '',
    });
    await load();
  }

  async function reissue(customer: Customer) {
    const reason = window.prompt('سبب إعادة إصدار الرمز؟');
    if (!reason || reason.trim().length < 3) return;

    const result = await callRpc<{ qr_token: string }>('fn_reissue_qr', {
      p_customer_id: customer.id,
      p_reason: reason,
    });

    if (!result.ok) {
      setError(result.message ?? errorText(result.code));
      return;
    }

    setIssued({
      token: result.data.qr_token,
      no: customer.customer_no,
      property: customer.properties?.name ?? '',
    });
    await load();
  }

  const term = search.trim();
  const filtered = term
    ? rows.filter(
        (row) =>
          String(row.customer_no).includes(term) ||
          row.full_name?.includes(term) ||
          row.phone?.includes(term),
      )
    : rows;

  if (issued) {
    return (
      <section>
        <header className="screen-header">
          <h2>رمز العميل</h2>
          <button type="button" onClick={() => setIssued(null)}>
            رجوع
          </button>
        </header>

        <QrCard token={issued.token} customerNo={issued.no} propertyName={issued.property} />
      </section>
    );
  }

  return (
    <section>
      <header className="screen-header">
        <h2>العملاء</h2>
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <div className="form">
        <label htmlFor="new-customer">إنشاء عميل جديد — اختر العقار</label>
        <select
          id="new-customer"
          defaultValue=""
          onChange={(event) => {
            if (event.target.value) {
              void createCustomer(event.target.value);
              event.target.value = '';
            }
          }}
        >
          <option value="" disabled>
            اختر عقارًا…
          </option>
          {properties.map((property) => (
            <option key={property.id} value={property.id}>
              {property.code} — {property.name}
            </option>
          ))}
        </select>
        {properties.length === 0 && <p className="muted">أضف عقارًا فعّالًا أولًا.</p>}
      </div>

      <div className="form">
        <label htmlFor="search">بحث</label>
        <input
          id="search"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="رقم العميل أو الاسم أو الهاتف"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="empty">لا يوجد عملاء مطابقون.</p>
      ) : (
        <ul className="cards">
          {filtered.map((customer) => (
            <li key={customer.id} className="card">
              <div className="card-main">
                <strong>{customer.full_name ?? `عميل ${customer.customer_no}`}</strong>
                <span className="muted">
                  {customer.properties?.name}
                  {customer.floor_number && ` · ط${customer.floor_number}`}
                  {customer.apartment_number && ` ش${customer.apartment_number}`}
                </span>
                {/* الهاتف مُقنَّع: لا داعي لعرضه كاملًا في قائمة */}
                {customer.phone && (
                  <span className="muted">{`+968 ****${customer.phone.slice(-2)}`}</span>
                )}
              </div>

              <div className="card-actions">
                <span
                  className={customer.profile_status === 'complete' ? 'badge-on' : 'badge-warn'}
                >
                  {customer.profile_status === 'complete' ? 'مكتمل' : 'غير مكتمل'}
                </span>

                <button type="button" onClick={() => void reissue(customer)}>
                  إعادة إصدار QR
                </button>

                {canDisable && (
                  <button
                    type="button"
                    onClick={async () => {
                      const result = await callRpc('fn_set_customer_active', {
                        p_customer_id: customer.id,
                        p_active: !customer.is_active,
                      });
                      if (!result.ok) setError(errorText(result.code));
                      else await load();
                    }}
                  >
                    {customer.is_active ? 'إيقاف' : 'تفعيل'}
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
