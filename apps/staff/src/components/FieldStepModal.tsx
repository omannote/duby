import { useEffect, useRef, useState } from 'react';
import { normalizeQrToken } from '@duby/shared';
import { cameraErrorMessage, startScanner, type ScannerHandle } from '../lib/scanner.js';
import { callOrdersApi, uploadPhoto } from '../lib/orders-api.js';
import { compressPhoto, type CompressedPhoto } from '../lib/image.js';

type UploadUrlData = { upload_url: string; storage_path: string };
type OrderData = { id: string; status: string };

/**
 * نافذة الاستلام والتسليم.
 *
 * ثلاثة قرارات هنا تقابل أعطالًا حقيقية:
 *  • التذييل خارج منطقة التمرير، فلا تختفي الأزرار خلف شريط التنقل.
 *  • النافذة لا تُغلق إلا بعد أن تعيد قاعدة البيانات الحالة الجديدة محفوظة.
 *  • الخطأ يظهر داخل النافذة لا خلفها، برمزه ومعرّف الطلب.
 */
export function FieldStepModal({
  orderId,
  step,
  onDone,
  onClose,
}: {
  orderId: string;
  step: 'pickup' | 'delivery';
  onDone: () => void;
  onClose: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const handleRef = useRef<ScannerHandle | null>(null);

  const [scanned, setScanned] = useState<string | null>(null);
  const [manual, setManual] = useState('');
  const [photo, setPhoto] = useState<CompressedPhoto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [stage, setStage] = useState<'idle' | 'uploading' | 'confirming'>('idle');

  useEffect(() => {
    let cancelled = false;

    void (async () => {
      const video = videoRef.current;
      if (!video) return;

      try {
        const handle = await startScanner(video, (value) => {
          const token = normalizeQrToken(value);
          if (!token) return;
          setScanned(token);
          handleRef.current?.stop();
        });

        if (cancelled) handle.stop();
        else handleRef.current = handle;
      } catch (cause) {
        if (!cancelled) setCameraError(cameraErrorMessage(cause));
      }
    })();

    return () => {
      cancelled = true;
      handleRef.current?.stop();
    };
  }, []);

  async function pickPhoto(file: File | undefined) {
    if (!file) return;
    setError(null);
    try {
      setPhoto(await compressPhoto(file));
    } catch {
      setError('تعذّر قراءة الصورة. أعد الالتقاط.');
    }
  }

  async function confirm() {
    const token = scanned ?? normalizeQrToken(manual);

    if (!token) {
      setError('امسح رمز العميل أو الصق رابطه.');
      return;
    }

    if (!photo) {
      setError('التقط صورة في الموقع قبل التأكيد.');
      return;
    }

    setBusy(true);
    setError(null);
    setStage('uploading');

    const urlResult = await callOrdersApi<UploadUrlData>('/photo-upload-url', {
      content_type: 'image/jpeg',
      byte_size: photo.blob.size,
    });

    if (!urlResult.ok) {
      setBusy(false);
      setStage('idle');
      setError(`${urlResult.message} (${urlResult.requestId.slice(0, 6)})`);
      return;
    }

    if (!(await uploadPhoto(urlResult.data.upload_url, photo.blob))) {
      setBusy(false);
      setStage('idle');
      setError('تعذّر رفع الصورة. تحقّق من الشبكة وحاول مجددًا.');
      return;
    }

    setStage('confirming');

    const result = await callOrdersApi<OrderData>('/field-step', {
      order_id: orderId,
      step,
      qr_token: token,
      storage_path: urlResult.data.storage_path,
    });

    setBusy(false);
    setStage('idle');

    // النافذة تبقى مفتوحة عند الفشل، والخطأ يظهر داخلها
    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    // لا تُغلق إلا وقد أعادت قاعدة البيانات الحالة الجديدة محفوظة
    handleRef.current?.stop();
    onDone();
  }

  const title = step === 'pickup' ? 'تأكيد الاستلام' : 'تأكيد التسليم';

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label={title}>
      <div className="modal">
        <header className="modal-header">
          <h3>{title}</h3>
          <button
            type="button"
            className="icon"
            onClick={onClose}
            aria-label="إغلاق"
            disabled={busy}
          >
            ✕
          </button>
        </header>

        <div className="modal-body">
          <p className="muted">امسح رمز العميل، ثم التقط صورة في الموقع.</p>

          <div className="scanner">
            <video ref={videoRef} playsInline muted aria-label="ماسح الكاميرا" />
            {scanned && <div className="scanner-ok">✓ تم التقاط الرمز</div>}
          </div>

          {cameraError && <p className="warn">{cameraError}</p>}

          {/* البديل اليدوي متاح دائمًا: قارئ USB يكتب هنا مباشرة */}
          <label htmlFor="manual-qr">أو الصق رابط الرمز</label>
          <input
            id="manual-qr"
            value={manual}
            onChange={(event) => setManual(event.target.value)}
            placeholder="https://qr.myduby.com/?t=…"
            disabled={Boolean(scanned)}
          />

          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            onChange={(event) => void pickPhoto(event.target.files?.[0])}
          />

          {photo ? (
            <img className="field-photo" src={photo.previewUrl} alt="صورة الموقع" />
          ) : (
            <div className="field-photo placeholder">لا توجد صورة بعد</div>
          )}

          <button type="button" onClick={() => fileRef.current?.click()} disabled={busy}>
            {photo ? 'التقاط صورة أخرى' : 'التقاط صورة الموقع'}
          </button>

          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
        </div>

        {/* التذييل خارج منطقة التمرير: الأزرار ظاهرة دائمًا مهما طال المحتوى */}
        <footer className="modal-footer">
          <button type="button" className="ghost" onClick={onClose} disabled={busy}>
            إلغاء
          </button>
          <button type="button" onClick={() => void confirm()} disabled={busy}>
            {stage === 'uploading'
              ? 'جارٍ رفع الصورة…'
              : stage === 'confirming'
                ? 'جارٍ التأكيد…'
                : 'حفظ وتأكيد'}
          </button>
        </footer>
      </div>
    </div>
  );
}
