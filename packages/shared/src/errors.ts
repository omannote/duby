/**
 * رموز الأخطاء الموحّدة — المصدر الوحيد لها.
 * العقد الكامل في docs/plan/05-api-contracts.md
 *
 * قاعدة: كل رمز هنا له اختبار يُنتجه. رمز بلا اختبار = رمز غير موجود فعليًا.
 */
export const ERROR_CODES = [
  // عام
  'invalid_input',
  'forbidden',
  'server_error',
  'app_outdated',
  'rate_limited',

  // رمز QR والعميل
  'invalid_qr',
  'revoked_qr',
  'inactive_customer',
  'inactive_property',
  'profile_incomplete',

  // التحقق
  'otp_required',
  'otp_invalid',
  'otp_expired',
  'otp_blocked',
  'submission_expired',
  'submission_consumed',

  // الطلبات
  'order_not_found',
  'stale_state',
  'invalid_transition',
  'qr_mismatch',
  'photo_required',
  'photo_rejected',

  // المال
  'payment_required',
  'duplicate_invoice',
  'provider_error',

  // الصندوق
  'unhanded_cash',
  'settlement_locked',
  'settlement_closed',
  'self_verification',
  'variance_needs_approval',
  'proof_required',
  'proof_reused',
  'exception_reason_required',
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

/** الرسائل العربية المعروضة للمستخدم. لا رسالة عامة بلا رمز. */
export const ERROR_MESSAGES: Record<ErrorCode, string> = {
  invalid_input: 'البيانات المدخلة غير صحيحة',
  forbidden: 'ليس لديك صلاحية لهذه العملية',
  server_error: 'حدث خطأ غير متوقع',
  app_outdated: 'يتوفر إصدار جديد — حدّث التطبيق للمتابعة',
  rate_limited: 'تجاوزت عدد المحاولات المسموح، حاول لاحقًا',

  invalid_qr: 'رمز غير صالح',
  revoked_qr: 'هذا الرمز أُبطل — اطلب رمزًا جديدًا',
  inactive_customer: 'هذا الحساب غير مفعّل',
  inactive_property: 'العقار غير مفعّل حاليًا',
  profile_incomplete: 'أكمل بياناتك أولًا',

  otp_required: 'يلزم التحقق من رقم هاتفك',
  otp_invalid: 'رمز التحقق غير صحيح',
  otp_expired: 'انتهت صلاحية رمز التحقق',
  otp_blocked: 'تم إيقاف المحاولات مؤقتًا',
  submission_expired: 'انتهت مهلة إرسال الطلب، ابدأ من جديد',
  submission_consumed: 'تم إرسال هذا الطلب مسبقًا',

  order_not_found: 'الطلب غير موجود',
  stale_state: 'تغيّرت حالة الطلب — سنعيد التحميل',
  invalid_transition: 'لا يمكن الانتقال إلى هذه الحالة',
  qr_mismatch: 'الرمز الممسوح لا يخص عميل هذا الطلب',
  photo_required: 'الصورة إلزامية',
  photo_rejected: 'تعذّر قبول الصورة، أعد الالتقاط',

  payment_required: 'لا يمكن التسليم قبل تسجيل الدفع',
  duplicate_invoice: 'رقم الفاتورة مستخدم مسبقًا',
  provider_error: 'تعذّر الاتصال بمزوّد الخدمة، حاول مجددًا',

  unhanded_cash: 'لديك نقد غير مودَع — أودعه أولًا',
  settlement_locked: 'التسوية معتمدة ولا يمكن تعديلها',
  settlement_closed: 'التسوية مُودَعة ولا تقبل تحصيلات جديدة',
  self_verification: 'لا يمكنك اعتماد تسويتك — يعتمدها زميل من المشغّلين',
  variance_needs_approval: 'الفرق يتجاوز حد السماح ويحتاج اعتماد المشرف',
  proof_required: 'يلزم رقم الإيصال وصورته',
  proof_reused: 'هذا الإثبات مستخدم في تسوية سابقة',
  exception_reason_required: 'اكتب سبب عدم الإيداع البنكي',
};

/** نص الخطأ المعروض، متبوعًا بمعرّف الطلب لتشخيص من بلاغ واحد. */
export function errorText(code: ErrorCode, requestId?: string): string {
  const message = ERROR_MESSAGES[code] ?? ERROR_MESSAGES.server_error;
  return requestId ? `${message} (${requestId.slice(0, 6)})` : message;
}
