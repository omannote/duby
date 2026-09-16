/**
 * صفحتا العودة من بوابة الدفع.
 *
 * لا تؤكدان شيئًا ولا تستعلمان: معامل `success` في الرابط ليس دليل دفع، وهذه
 * صفحة عامة يمكن لأي أحد فتحها بأي وسائط. التأكيد يأتي من webhook ثواني، أو
 * من استعلام الموظف، أو من المصالحة الدورية — ثلاث طبقات كلها على الخادم.
 */
export function PaymentReturn({ outcome }: { outcome: 'success' | 'cancel' }) {
  if (outcome === 'cancel') {
    return (
      <div className="step done">
        <div className="check cancel" aria-hidden="true">
          ✕
        </div>
        <h1>لم تكتمل عملية الدفع</h1>
        <p>يمكنك المحاولة مجددًا من رابط الدفع المرسل إليك عبر واتساب.</p>
      </div>
    );
  }

  return (
    <div className="step done">
      <div className="check" aria-hidden="true">
        ✓
      </div>
      <h1>شكرًا لك</h1>
      <p>نتحقق من عملية الدفع مع البنك الآن.</p>
      <p className="muted">سيصلك إشعار عبر واتساب فور تأكيدها. لا حاجة لإعادة الدفع.</p>
    </div>
  );
}
