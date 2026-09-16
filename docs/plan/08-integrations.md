# 08 — التكاملات

## 1. مبدأ عام

كل مزود خارجي خلف **واجهة مجرّدة** في `packages/shared`. المزود يتغير دون لمس
منطق الطلبات.

```ts
interface NotificationProvider {
  sendTemplate(input: {
    to: string;              // 968XXXXXXXX
    template: string;
    params: string[];
    language: 'ar' | 'en';
    idempotencyKey: string;
  }): Promise<{ ok: true; messageId: string } | { ok: false; code: string }>;
}

interface PaymentProvider {
  createSession(input: CreateSessionInput): Promise<SessionResult>;
  retrieveSession(sessionId: string): Promise<SessionStatus>;
  verifyWebhook(rawBody: string, signature: string): boolean;
}
```

التطبيقات: `WhatsAppBridgeProvider`, `ThawaniProvider`, وفي الاختبارات
`FakeNotificationProvider` و`FakePaymentProvider`. لا اختبار يلمس مزودًا حقيقيًا.

---

## 2. WhatsApp Bridge

### الإعداد

```
WHATSAPP_BRIDGE_BASE_URL   https://myduby.com/whatsapp/api
WHATSAPP_BRIDGE_API_KEY    wab_live_…            (أسرار Edge Functions فقط)
WHATSAPP_OTP_TEMPLATE      order_confirmation_v2
WHATSAPP_STATUS_TEMPLATE   ar_template
WHATSAPP_LANGUAGE          ar
WHATSAPP_OTP_GREETING      عميلنا العزيز
WHATSAPP_TIMEOUT_MS        15000
```

### الطلب

```http
POST /messages/send-notification
Content-Type: application/json
X-API-Key: {WHATSAPP_BRIDGE_API_KEY}

{ "to": "96891234567", "template_name": "order_confirmation_v2",
  "params": ["عميلنا العزيز", "482913"], "language": "ar", "image_url": null }
```

### القالبان

| القالب | المتغيرات | القاعدة |
|---|---|---|
| `order_confirmation_v2` | `{{1}}` تحية، `{{2}}` رمز | **متغيران إلزامًا** وإلا يُرفض الإرسال |
| `ar_template` | `{{1}}` نص الحالة | **متغير واحد فقط** |

نموذج نص حالة:

> عميلنا العزيز،
> لقد تم تحديث حالة طلبكم إلى: تم الاستلام
> شكراً لاختياركم دوبي — نظافة تستحق ثقتكم.

### توحيد الأرقام

```ts
function normalizeOmani(raw: string): string | null {
  const d = raw.replace(/\D/g, '');
  if (/^[79]\d{7}$/.test(d))          return `+968${d}`;
  if (/^968[79]\d{7}$/.test(d))       return `+${d}`;
  if (/^00968[79]\d{7}$/.test(d))     return `+${d.slice(2)}`;
  return null;
}
```

التخزين `+968XXXXXXXX`؛ الإرسال للجسر بلا `+`.

### القواعد

1. HTTPS فقط، مهلة 15 ثانية.
2. المفتاح لا يظهر في أي سجل — تنقيح صريح.
3. **رمز OTP لا يُسجَّل في أي مكان** ولا يمر عبر Outbox.
4. كل إرسال له `idempotencyKey`.
5. استجابة المزود تُخزَّن منقّحة في `safe_payload`.
6. فشل الإرسال لا يُرجع حالة الطلب.

### مسارا الإرسال

| | OTP | تحديث الحالة |
|---|---|---|
| المسار | إرسال مباشر من `public-qr` | Outbox ← `notifications` |
| التخزين | لا شيء — الرمز مجزَّأ فقط | `params` في الطابور |
| عند الفشل | خطأ فوري للعميل | إعادة محاولة تلقائية |
| السبب | الفورية إلزامية، والتخزين محظور | الفورية غير إلزامية، والموثوقية أهم |

### نمط Outbox

```
تغيّر الحالة (داخل المعاملة)
  └─ محفّز: إدراج pending في private.notification_outbox
       ↓ (خارج المعاملة — pg_cron كل دقيقة)
  دالة notifications
    ├─ SELECT … FOR UPDATE SKIP LOCKED LIMIT 50
    ├─ إرسال
    ├─ نجاح ← sent + provider_msg_id
    └─ فشل  ← failed + تراجع أسّي: 1د، 5د، 15د، 60د، 6س
              بعد 5 محاولات ← dead + تنبيه
```

`SKIP LOCKED` يسمح بعمّال متوازين بلا تعارض. `idempotency_key` الفريد يضمن ألا
يصل إشعار مكرر حتى لو أُعيد تشغيل الدورة.

### قياس الصحة

| المقياس | الحد |
|---|---|
| عناصر `pending` أقدم من 5 دقائق | > 10 ← تنبيه |
| نسبة `failed` خلال ساعة | > 20% ← تنبيه |
| أي عنصر `dead` | تنبيه فوري |

---

## 3. Thawani

### الإعداد

```
THAWANI_MODE              uat | live
THAWANI_API_BASE_URL      https://uatcheckout.thawani.om
THAWANI_SECRET_KEY        …                (أسرار Edge Functions فقط)
THAWANI_PUBLISHABLE_KEY   …
THAWANI_WEBHOOK_SECRET    …
THAWANI_SUCCESS_URL       https://qr.myduby.com/payment/success
THAWANI_CANCEL_URL        https://qr.myduby.com/payment/cancel
```

### إنشاء الجلسة

```http
POST /api/v1/checkout/session
thawani-api-key: {SECRET}

{ "client_reference_id": "{order_id}",
  "mode": "payment",
  "products": [{ "name": "طلب غسيل QR-1042", "quantity": 1, "unit_amount": 4500 }],
  "success_url": "…/payment/success?rt={return_token}",
  "cancel_url":  "…/payment/cancel?rt={return_token}",
  "metadata": { "order_no": "1042", "invoice": "INV-2026-0042" } }
```

- `unit_amount` **بالبيسة**: `round(amount_omr * 1000)`.
- `return_token` عشوائي، يُخزَّن **مجزَّأً** فقط، ولا يُعتبر دليل دفع.
- `client_reference_id` يربط الجلسة بالطلب عند المصالحة.

### ثلاث طبقات للتأكيد

```
1. Webhook (أساسي)
   ثواني → payments-webhook → التحقق من التوقيع → fn_apply_payment_webhook

2. استعلام عند العودة (احتياطي)
   العميل يفتح /payment/success?rt=… → استعلام عن الجلسة → تطبيق النتيجة

3. مصالحة دورية (شبكة أمان)
   كل 15 دقيقة: لكل جلسة معلّقة > 10 دقائق → استعلام → تطبيق
```

النظام الحالي يملك الطبقة الثانية وحدها. النتيجة العملية: عميل يدفع ثم يغلق
المتصفح ← الطلب يبقى `unpaid` ← لا يمكن تسليمه.

### التحقق من الـwebhook

```ts
function verify(raw: string, sig: string, secret: string): boolean {
  const expected = hmacSha256Hex(raw, secret);
  return timingSafeEqual(expected, sig);   // مقارنة ثابتة الزمن
}
```

1. التحقق **قبل** تحليل الجسم.
2. توقيع غير صالح ← `401` فورًا مع تسجيل المحاولة.
3. المعالجة معادة الأمان عبر `provider_session_id`.
4. الإعادة `200` بعد المعالجة دائمًا.
5. كل استدعاء يُسجَّل في `payment_events` حتى لو لم يغيّر شيئًا.

### القواعد المالية

| # | القاعدة |
|---|---|
| 1 | المفتاح السري لا يصل للمتصفح بأي حال |
| 2 | كل نداء لثواني من الخادم فقط |
| 3 | `success=true` في الرابط ليس دليل دفع |
| 4 | `payment_status = paid` فقط بتأكيد من المزود أو دفع نقدي مسجّل |
| 5 | المبالغ `DECIMAL(12,3)` — لا `FLOAT` إطلاقًا |
| 6 | فشل الجلسة ← لا فاتورة ولا انتقال حالة (معاملة واحدة) |
| 7 | دفع أكدته ثواني لا يُلغى يدويًا |
| 8 | كل عملية لها `idempotency_key` فريد |

### الانتقال من UAT إلى الإنتاج

- [ ] مفاتيح الإنتاج في أسرار Supabase (الإنتاج فقط)
- [ ] `THAWANI_API_BASE_URL` محدّث
- [ ] رابط الـwebhook مسجَّل في لوحة ثواني
- [ ] دفعة حقيقية بقيمة صغيرة تُختبر من طرف إلى طرف
- [ ] اختبار استرداد
- [ ] تأكيد وصول الـwebhook وتسجيله
- [ ] مهمة المصالحة تعمل على الإنتاج

---

## 4. التعامل مع أعطال المزودين

| العطل | السلوك |
|---|---|
| مهلة عند إنشاء جلسة | تراجع المعاملة، رسالة «تعذّر إنشاء رابط الدفع، حاول مجددًا» |
| ثواني يعيد 5xx | 3 محاولات بتراجع، ثم `provider_error` |
| webhook متأخر | المصالحة تلتقطه خلال 15 دقيقة |
| webhook مكرر | `idempotency` ← لا أثر للثاني |
| جسر واتساب معطّل | OTP يفشل فورًا برسالة صريحة؛ إشعارات الحالة تتراكم في الطابور وتُرسل عند العودة |
| قالب واتساب مرفوض | `dead` + تنبيه + عرض المشكلة في لوحة الإدارة |

---

## 5. التكاملات المؤجلة

| التكامل | الغرض | المتطلب |
|---|---|---|
| مزود SMS احتياطي | استمرارية OTP عند تعطل واتساب | تطبيق ثانٍ لـ`NotificationProvider` |
| خرائط Google Directions | ترتيب جولات المندوبين | المرحلة التالية |
| تصدير محاسبي | ربط الفواتير بنظام محاسبة | تحديد النظام المستهدف |
| بوابة عميل | متابعة الطلب بلا حساب | رابط موقّع قصير الصلاحية |

كل واحد منها يدخل عبر الواجهة المجرّدة نفسها — لا تعديل على منطق الطلبات.
