import jsQR from 'jsqr';

/**
 * ماسح QR بثلاث طبقات.
 *
 * الطبقة الثانية ليست احتياطية اختيارية: Safari على iPhone لا يدعم
 * BarcodeDetector، وهو الجهاز الذي يعمل عليه معظم مندوبينا. الاعتماد على
 * الطبقة الأولى وحدها عطّل المسح مرتين في النظام السابق.
 */
export type ScannerLayer = 'barcode-detector' | 'frame-analysis' | 'manual';

export type ScannerHandle = {
  layer: ScannerLayer;
  stop: () => void;
};

type BarcodeDetectorLike = {
  detect: (source: CanvasImageSource) => Promise<{ rawValue: string }[]>;
};

function barcodeDetector(): BarcodeDetectorLike | null {
  const ctor = (
    window as unknown as {
      BarcodeDetector?: new (options: { formats: string[] }) => BarcodeDetectorLike;
    }
  ).BarcodeDetector;

  if (!ctor) return null;

  try {
    return new ctor({ formats: ['qr_code'] });
  } catch {
    return null;
  }
}

export async function startScanner(
  video: HTMLVideoElement,
  onResult: (value: string) => void,
): Promise<ScannerHandle> {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: {
      facingMode: { ideal: 'environment' },
      width: { ideal: 1280 },
      height: { ideal: 720 },
    },
  });

  video.srcObject = stream;
  video.setAttribute('playsinline', 'true'); // إلزامي على iOS وإلا فُتح الفيديو ملء الشاشة
  video.muted = true;
  await video.play();

  const detector = barcodeDetector();
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d', { willReadFrequently: true });

  let running = true;
  let frame = 0;

  const stop = () => {
    running = false;
    cancelAnimationFrame(frame);
    // إيقاف كل المسارات: عدمه يترك الكاميرا مضاءة بعد إغلاق النافذة
    for (const track of stream.getTracks()) track.stop();
    video.srcObject = null;
  };

  const tick = async () => {
    if (!running) return;

    if (video.readyState === video.HAVE_ENOUGH_DATA) {
      if (detector) {
        try {
          const found = await detector.detect(video);
          if (found[0]?.rawValue) {
            onResult(found[0].rawValue);
            return;
          }
        } catch {
          // نواصل بتحليل الإطارات
        }
      } else if (context) {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0, canvas.width, canvas.height);

        const image = context.getImageData(0, 0, canvas.width, canvas.height);
        const found = jsQR(image.data, image.width, image.height, {
          inversionAttempts: 'dontInvert',
        });

        if (found?.data) {
          onResult(found.data);
          return;
        }
      }
    }

    frame = requestAnimationFrame(() => void tick());
  };

  frame = requestAnimationFrame(() => void tick());

  return { layer: detector ? 'barcode-detector' : 'frame-analysis', stop };
}

/** رسالة إذن الكاميرا بلغة الموظف، مع البديل اليدوي دائمًا متاحًا. */
export function cameraErrorMessage(error: unknown): string {
  const name = error instanceof Error ? error.name : '';

  if (name === 'NotAllowedError') {
    return 'الكاميرا غير مسموحة. فعّلها من إعدادات الجهاز ← الخصوصية ← الكاميرا، أو استخدم القارئ الخارجي.';
  }

  if (name === 'NotFoundError') {
    return 'لا توجد كاميرا في هذا الجهاز. استخدم القارئ الخارجي أو الصق الرابط.';
  }

  return 'تعذّر تشغيل الكاميرا. استخدم القارئ الخارجي أو الصق الرابط.';
}
