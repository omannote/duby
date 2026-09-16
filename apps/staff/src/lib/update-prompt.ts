import { registerSW } from 'virtual:pwa-register';

/**
 * يعلن التحديث بدل تطبيقه صامتًا.
 *
 * «أي نسخة تعمل عليها؟» كان سؤالًا يستهلك جولات تشخيص في النظام السابق.
 * هنا: الإصدار ظاهر في الواجهة، ويُرسل في X-App-Version، والتحديث معلن.
 */
export function watchForUpdates(onAvailable: (apply: () => void) => void): void {
  const update = registerSW({
    immediate: true,
    onNeedRefresh() {
      onAvailable(() => void update(true));
    },
  });
}
