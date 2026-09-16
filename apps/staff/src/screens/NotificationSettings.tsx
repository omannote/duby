import { useCallback, useEffect, useState } from 'react';
import {
  ORDER_STATUS_LABELS,
  atLeast,
  errorText,
  type OrderStatus,
  type StaffRole,
} from '@duby/shared';
import { supabase } from '../supabase.js';
import { callRpc } from '../lib/api.js';

type Setting = {
  status: OrderStatus;
  label_ar: string;
  sort_order: number;
  notify_enabled: boolean;
  notification_message: string;
};

/**
 * إعدادات إشعارات الحالات.
 *
 * المعاينة تعرض الرسالة كما يراها العميل في واتساب — القالب `ar_template`
 * يقبل متغيرًا واحدًا، فما يُكتب هنا هو نص الرسالة كاملًا.
 */
export function NotificationSettings({ role }: { role: StaffRole }) {
  const [rows, setRows] = useState<Setting[]>([]);
  const [drafts, setDrafts] = useState<Record<string, Setting>>({});
  const [error, setError] = useState<string | null>(null);
  const [savingStatus, setSavingStatus] = useState<string | null>(null);

  const canEdit = atLeast(role, 'manager');

  const load = useCallback(async () => {
    if (!supabase) return;

    const { data, error: loadError } = await supabase
      .from('order_status_settings')
      .select('status, label_ar, sort_order, notify_enabled, notification_message')
      .order('sort_order');

    if (loadError) setError('تعذّر تحميل الإعدادات');
    else {
      const list = (data ?? []) as Setting[];
      setRows(list);
      setDrafts(Object.fromEntries(list.map((row) => [row.status, row])));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function save(status: OrderStatus) {
    const draft = drafts[status];
    if (!draft) return;

    setSavingStatus(status);
    setError(null);

    const result = await callRpc('fn_update_status_setting', {
      p_status: status,
      p_notify_enabled: draft.notify_enabled,
      p_message: draft.notification_message,
    });

    setSavingStatus(null);

    if (!result.ok) {
      setError(result.message ?? errorText(result.code));
      return;
    }

    await load();
  }

  function update(status: OrderStatus, patch: Partial<Setting>) {
    setDrafts((current) => {
      const existing = current[status];
      if (!existing) return current;
      return { ...current, [status]: { ...existing, ...patch } };
    });
  }

  return (
    <section>
      <header className="screen-header">
        <h2>إشعارات الحالات</h2>
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {!canEdit && <p className="muted">العرض فقط — التعديل لمن هم بدرجة مشرف فأعلى.</p>}

      <ul className="cards">
        {rows.map((row) => {
          const draft = drafts[row.status] ?? row;
          const changed =
            draft.notify_enabled !== row.notify_enabled ||
            draft.notification_message !== row.notification_message;

          return (
            <li key={row.status} className="card setting-card">
              <div className="setting-head">
                <strong>{ORDER_STATUS_LABELS[row.status]}</strong>
                <label className="switch">
                  <input
                    type="checkbox"
                    checked={draft.notify_enabled}
                    disabled={!canEdit}
                    onChange={(event) =>
                      update(row.status, { notify_enabled: event.target.checked })
                    }
                  />
                  {draft.notify_enabled ? 'مفعّل' : 'معطّل'}
                </label>
              </div>

              <label htmlFor={`msg-${row.status}`}>نص الرسالة</label>
              <textarea
                id={`msg-${row.status}`}
                value={draft.notification_message}
                disabled={!canEdit}
                rows={2}
                onChange={(event) =>
                  update(row.status, { notification_message: event.target.value })
                }
              />

              {/* المعاينة: ما يصل العميل فعلًا */}
              <div className="preview-bubble">
                <span className="muted">معاينة واتساب</span>
                <p>{draft.notification_message || '—'}</p>
                {row.status === 'out_for_delivery' && (
                  <p className="muted">رابط الدفع:{'\n'}https://…</p>
                )}
              </div>

              {!draft.notify_enabled && (
                <p className="muted">معطّل: يُسجَّل الإشعار كـ«متجاوَز» في سجل الطلب ولا يُرسل.</p>
              )}

              {canEdit && changed && (
                <button
                  type="button"
                  onClick={() => void save(row.status)}
                  disabled={savingStatus === row.status}
                >
                  {savingStatus === row.status ? 'جارٍ الحفظ…' : 'حفظ'}
                </button>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
