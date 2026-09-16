import { useCallback, useEffect, useState } from 'react';
import { callRpc } from '../lib/api.js';

/*
 * ما لا يُفحص آليًا يُنسى. البنود هنا كلها أشياء لو نقصت لانكسر شيء في أول
 * يوم: مندوب لا يعرف أين يودع، مهلة تُحسب بأيام تقويمية، رمز مطبوع لا يفتح
 * شيئًا. تختفي البطاقة كلها متى مرّ كل بند — فلا تصير زينة دائمة.
 */
type Check = { key: string; label: string; passed: boolean; impact: string };
type Readiness = { ready: boolean; checks: Check[]; checked_at: string };

export function LaunchReadiness() {
  const [readiness, setReadiness] = useState<Readiness | null>(null);

  const load = useCallback(async () => {
    const result = await callRpc<Readiness>('fn_launch_readiness', {});
    if (result.ok) setReadiness(result.data);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (!readiness || readiness.ready) return null;

  const pending = readiness.checks.filter((check) => !check.passed);

  return (
    <section className="readiness" aria-labelledby="readiness-title">
      <h3 id="readiness-title">جاهزية الإطلاق — {pending.length} بندًا ناقصًا</h3>
      <ul>
        {pending.map((check) => (
          <li key={check.key}>
            <strong>{check.label}</strong>
            <span className="muted">{check.impact}</span>
          </li>
        ))}
      </ul>
      <button type="button" className="ghost" onClick={() => void load()}>
        إعادة الفحص
      </button>
    </section>
  );
}
