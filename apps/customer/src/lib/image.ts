/**
 * ضغط صورة الطلب في المتصفح قبل الرفع.
 *
 * بديل `Image` ضروري لا تحسيني: بعض صور iPhone لا يعمل معها
 * `createImageBitmap`، وبدونه يفشل الرفع على الجهاز الأكثر استخدامًا لدينا.
 */
const MAX_EDGE = 1600;
const TARGET_BYTES = 1_500_000;
const QUALITY_STEPS = [0.8, 0.7, 0.6, 0.5] as const;

async function loadImage(
  file: File,
): Promise<{ width: number; height: number; source: CanvasImageSource }> {
  if ('createImageBitmap' in window) {
    try {
      const bitmap = await createImageBitmap(file);
      return { width: bitmap.width, height: bitmap.height, source: bitmap };
    } catch {
      // نسقط إلى Image بدل الفشل
    }
  }

  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.decoding = 'async';
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('image_decode_failed'));
      image.src = url;
    });
    return { width: image.naturalWidth, height: image.naturalHeight, source: image };
  } finally {
    URL.revokeObjectURL(url);
  }
}

function toBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

export type CompressedPhoto = { blob: Blob; width: number; height: number; previewUrl: string };

export async function compressPhoto(file: File): Promise<CompressedPhoto> {
  const { width, height, source } = await loadImage(file);

  const scale = Math.min(1, MAX_EDGE / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);

  const context = canvas.getContext('2d');
  if (!context) throw new Error('canvas_unavailable');
  context.drawImage(source, 0, 0, canvas.width, canvas.height);

  // هبوط تدريجي في الجودة حتى الحجم الهدف
  for (const quality of QUALITY_STEPS) {
    const blob = await toBlob(canvas, quality);
    if (blob && blob.size <= TARGET_BYTES) {
      return {
        blob,
        width: canvas.width,
        height: canvas.height,
        previewUrl: URL.createObjectURL(blob),
      };
    }
  }

  const last = await toBlob(canvas, 0.4);
  if (!last) throw new Error('image_encode_failed');

  return {
    blob: last,
    width: canvas.width,
    height: canvas.height,
    previewUrl: URL.createObjectURL(last),
  };
}
