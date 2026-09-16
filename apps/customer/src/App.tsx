import { useCallback, useEffect, useState } from 'react';
import { normalizeQrToken } from '@duby/shared';
import { callApi } from './lib/api.js';
import { ProfileStep } from './screens/ProfileStep.js';
import { OtpStep } from './screens/OtpStep.js';
import { PhotoStep } from './screens/PhotoStep.js';
import { DoneStep } from './screens/DoneStep.js';

const APP_VERSION = import.meta.env.VITE_APP_VERSION ?? 'dev';

type ScanData = {
  scan_session_id: string;
  profile_status: 'incomplete' | 'complete';
  phone_masked: string | null;
  can_request_otp: boolean;
  resend_available_in: number;
};

type Step =
  | { name: 'checking' }
  | { name: 'blocked'; message: string; requestId: string }
  | { name: 'profile'; scan: ScanData }
  | { name: 'otp'; scan: ScanData }
  | { name: 'photo'; scan: ScanData; submissionToken: string }
  | { name: 'done'; orderNo: number };

export function App() {
  const [step, setStep] = useState<Step>({ name: 'checking' });

  const scan = useCallback(async () => {
    const token = normalizeQrToken(window.location.href);

    if (!token) {
      setStep({
        name: 'blocked',
        message: 'لا يوجد رمز في الرابط. امسح رمز QR الموجود في شقتك.',
        requestId: '',
      });
      return;
    }

    const result = await callApi<ScanData>('/scan', { token });

    if (!result.ok) {
      setStep({ name: 'blocked', message: result.message, requestId: result.requestId });
      return;
    }

    setStep(
      result.data.profile_status === 'complete'
        ? { name: 'otp', scan: result.data }
        : { name: 'profile', scan: result.data },
    );
  }, []);

  useEffect(() => {
    void scan();
  }, [scan]);

  return (
    <div className="page">
      <header>
        <span className="brand">دوبي</span>
        <span className="tagline">للغسيل السريع والجاف</span>
      </header>

      <main>
        {step.name === 'checking' && <p>جارٍ التحقق من الرمز…</p>}

        {step.name === 'blocked' && (
          <div className="blocked" role="alert">
            <h1>تعذّر المتابعة</h1>
            <p>{step.message}</p>
            {step.requestId && (
              <p className="request-id">رقم المرجع: {step.requestId.slice(0, 6)}</p>
            )}
          </div>
        )}

        {step.name === 'profile' && (
          <ProfileStep
            scanSessionId={step.scan.scan_session_id}
            onDone={() => setStep({ name: 'otp', scan: step.scan })}
          />
        )}

        {step.name === 'otp' && (
          <OtpStep
            scanSessionId={step.scan.scan_session_id}
            phoneMasked={step.scan.phone_masked}
            onVerified={(submissionToken) =>
              setStep({ name: 'photo', scan: step.scan, submissionToken })
            }
          />
        )}

        {step.name === 'photo' && (
          <PhotoStep
            submissionToken={step.submissionToken}
            onSubmitted={(orderNo) => setStep({ name: 'done', orderNo })}
          />
        )}

        {step.name === 'done' && <DoneStep orderNo={step.orderNo} />}
      </main>

      <footer>
        <p className="privacy">
          نحفظ اسمك ورقمك وصورة طلبك لتنفيذ الطلب فقط. تُحذف الصور بعد ١٨٠ يومًا.
        </p>
        <span className="version">الإصدار {APP_VERSION}</span>
      </footer>
    </div>
  );
}
