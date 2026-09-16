/**
 * يثبّت ارتفاع التطبيق على visualViewport بدل ارتفاع النافذة.
 * بدون هذا يتضخّم التخطيط عند فتح لوحة المفاتيح — عطل تكرر مرتين سابقًا.
 */
export function syncAppHeight(): () => void {
  const apply = () => {
    const height = window.visualViewport?.height ?? window.innerHeight;
    document.documentElement.style.setProperty('--app-height', `${height}px`);
  };

  apply();
  window.visualViewport?.addEventListener('resize', apply);
  window.addEventListener('orientationchange', apply);

  return () => {
    window.visualViewport?.removeEventListener('resize', apply);
    window.removeEventListener('orientationchange', apply);
  };
}
