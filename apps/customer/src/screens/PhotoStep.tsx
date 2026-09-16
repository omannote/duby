import { useRef, useState } from 'react';
import { callApi, uploadPhoto } from '../lib/api.js';
import { compressPhoto, type CompressedPhoto } from '../lib/image.js';

type UploadUrlData = { upload_url: string; storage_path: string };
type SubmitData = { order_no: number; duplicate: boolean };

/**
 * تصوير الطلب وإرساله.
 *
 * الطلب يُنشأ بعد رفع الصورة لا بعد نجاح التحقق، فلا تبقى طلبات بلا محتوى.
 * ورمز الإرسال صالح ١٥ دقيقة: فشل الرفع لا يُلزم العميل برمز تحقق جديد.
 */
export function PhotoStep({
  submissionToken,
  onSubmitted,
}: {
  submissionToken: string;
  onSubmitted: (orderNo: number) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [photo, setPhoto] = useState<CompressedPhoto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [stage, setStage] = useState<'idle' | 'compressing' | 'uploading' | 'submitting'>('idle');

  async function pick(file: File | undefined) {
    if (!file) return;

    setError(null);
    setStage('compressing');

    try {
      setPhoto(await compressPhoto(file));
    } catch {
      setError('تعذّر قراءة الصورة. جرّب التقاطها مرة أخرى.');
    } finally {
      setStage('idle');
    }
  }

  async function submit() {
    if (!photo) return;

    setBusy(true);
    setError(null);
    setStage('uploading');

    const urlResult = await callApi<UploadUrlData>('/photo-upload-url', {
      submission_token: submissionToken,
      content_type: 'image/jpeg',
      byte_size: photo.blob.size,
    });

    if (!urlResult.ok) {
      setBusy(false);
      setStage('idle');
      setError(`${urlResult.message} (${urlResult.requestId.slice(0, 6)})`);
      return;
    }

    const uploaded = await uploadPhoto(urlResult.data.upload_url, photo.blob);

    if (!uploaded) {
      setBusy(false);
      setStage('idle');
      setError('تعذّر رفع الصورة. تحقّق من الشبكة وحاول مجددًا.');
      return;
    }

    setStage('submitting');

    const submitResult = await callApi<SubmitData>('/submit-order', {
      submission_token: submissionToken,
      storage_path: urlResult.data.storage_path,
    });

    setBusy(false);
    setStage('idle');

    if (!submitResult.ok) {
      setError(`${submitResult.message} (${submitResult.requestId.slice(0, 6)})`);
      return;
    }

    onSubmitted(submitResult.data.order_no);
  }

  return (
    <div className="step">
      <h1>صوّر طلبك</h1>
      <p>التقط صورة واضحة للملابس قبل إرسال الطلب.</p>

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        hidden
        onChange={(event) => void pick(event.target.files?.[0])}
      />

      {photo ? (
        <div className="preview">
          <img src={photo.previewUrl} alt="معاينة صورة الطلب" />
        </div>
      ) : (
        <div className="preview placeholder">
          {stage === 'compressing' ? 'جارٍ تجهيز الصورة…' : 'لا توجد صورة بعد'}
        </div>
      )}

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <button type="button" onClick={() => inputRef.current?.click()} disabled={busy}>
        {photo ? 'التقاط صورة أخرى' : 'التقاط صورة'}
      </button>

      <button type="button" onClick={() => void submit()} disabled={!photo || busy}>
        {stage === 'uploading'
          ? 'جارٍ رفع الصورة…'
          : stage === 'submitting'
            ? 'جارٍ إرسال الطلب…'
            : 'إرسال الطلب'}
      </button>
    </div>
  );
}
