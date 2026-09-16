import { useEffect, useState } from 'react';
import QRCode from 'qrcode';

const CUSTOMER_BASE = import.meta.env.VITE_CUSTOMER_URL ?? 'https://qr.myduby.com';

/**
 * بطاقة QR للطباعة.
 *
 * الرمز لا يحمل أي بيانات شخصية — رابط و UUID عشوائي فقط. لا اسم ولا هاتف
 * ولا رقم شقة، فمن يلتقط صورة الملصق لا يحصل على شيء.
 */
export function QrCard({
  token,
  customerNo,
  propertyName,
}: {
  token: string;
  customerNo: number;
  propertyName: string;
}) {
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const url = `${CUSTOMER_BASE}/?t=${token}`;

  useEffect(() => {
    let active = true;

    void QRCode.toDataURL(url, { width: 512, margin: 1, errorCorrectionLevel: 'M' }).then(
      (result) => {
        if (active) setDataUrl(result);
      },
    );

    return () => {
      active = false;
    };
  }, [url]);

  return (
    <div className="qr-card">
      {dataUrl ? (
        <img src={dataUrl} alt={`رمز العميل رقم ${customerNo}`} width={220} height={220} />
      ) : (
        <div className="qr-placeholder">جارٍ التوليد…</div>
      )}

      <div className="qr-meta">
        <strong>عميل رقم {customerNo}</strong>
        <span className="muted">{propertyName}</span>
      </div>

      <div className="qr-actions no-print">
        <button type="button" onClick={() => window.print()}>
          طباعة
        </button>
        {dataUrl && (
          <a href={dataUrl} download={`duby-qr-${customerNo}.png`}>
            تنزيل
          </a>
        )}
      </div>
    </div>
  );
}
