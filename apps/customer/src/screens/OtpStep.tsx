import { useEffect, useState, type FormEvent } from 'react';
import { callApi } from '../lib/api.js';

type IssueData = { expires_in: number; resend_available_in: number; attempts_remaining: number };
type VerifyData = { submission_token: string };

export function OtpStep({
  scanSessionId,
  phoneMasked,
  onVerified,
}: {
  scanSessionId: string;
  phoneMasked: string | null;
  onVerified: (submissionToken: string) => void;
}) {
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setTimeout(() => setCooldown((value) => value - 1), 1000);
    return () => clearTimeout(timer);
  }, [cooldown]);

  async function request() {
    setBusy(true);
    setError(null);

    const result = await callApi<IssueData>('/request-otp', { scan_session_id: scanSessionId });

    setBusy(false);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    setSent(true);
    setCooldown(result.data.resend_available_in);
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const result = await callApi<VerifyData>('/verify-otp', {
      scan_session_id: scanSessionId,
      code,
    });

    setBusy(false);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      setCode('');
      return;
    }

    onVerified(result.data.submission_token);
  }

  if (!sent) {
    return (
      <div className="step">
        <h1>تأكيد رقمك</h1>
        <p>سنرسل رمز تحقق عبر واتساب إلى {phoneMasked ?? 'رقمك المسجّل'}.</p>

        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}

        <button type="button" onClick={() => void request()} disabled={busy}>
          {busy ? 'جارٍ الإرسال…' : 'إرسال رمز التحقق'}
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={verify} className="step">
      <h1>أدخل الرمز</h1>
      <p>أرسلنا رمزًا من ٦ أرقام إلى {phoneMasked ?? 'رقمك'}.</p>

      <label htmlFor="code">رمز التحقق</label>
      <input
        id="code"
        value={code}
        onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
        inputMode="numeric"
        autoComplete="one-time-code"
        className="otp-input"
        maxLength={6}
        required
      />

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <button type="submit" disabled={busy || code.length !== 6}>
        {busy ? 'جارٍ التحقق…' : 'تحقق'}
      </button>

      <button
        type="button"
        className="link"
        onClick={() => void request()}
        disabled={busy || cooldown > 0}
      >
        {cooldown > 0 ? `إعادة الإرسال بعد ${cooldown} ثانية` : 'إعادة إرسال الرمز'}
      </button>
    </form>
  );
}
