/**
 * ضغط صورة الموقع قبل الرفع.
 * بديل `Image` ضروري: بعض صور iPhone لا يعمل معها createImageBitmap.
 */
const MAX_EDGE = 1600;
const TARGET_BYTES = 1_500_000;

async function loadImage(file: File) {
  if ('createImageBitmap' in window) {
    try {
      const bitmap = await createImageBitmap(file);
      return { width: bitmap.width, height: bitmap.height, source: bitmap as CanvasImageSource };
    } catch {
      // نسقط إلى Image بدل الفشل
    }
  }

  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error('image_decode_failed'));
      image.src = url;
    });
    return {
      width: image.naturalWidth,
      height: image.naturalHeight,
      source: image as CanvasImageSource,
    };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export type CompressedPhoto = { blob: Blob; previewUrl: string };

export async function compressPhoto(file: File): Promise<CompressedPhoto> {
  const { width, height, source } = await loadImage(file);

  const scale = Math.min(1, MAX_EDGE / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);

  const context = canvas.getContext('2d');
  if (!context) throw new Error('canvas_unavailable');
  context.drawImage(source, 0, 0, canvas.width, canvas.height);

  for (const quality of [0.8, 0.7, 0.6, 0.5]) {
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', quality),
    );
    if (blob && blob.size <= TARGET_BYTES) {
      return { blob, previewUrl: URL.createObjectURL(blob) };
    }
  }

  const last = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, 'image/jpeg', 0.4),
  );
  if (!last) throw new Error('image_encode_failed');

  return { blob: last, previewUrl: URL.createObjectURL(last) };
}
