# 05 — عقود الواجهات

## 1. اصطلاحات عامة

### شكل الاستجابة

كل نقطة نهاية تُعيد الشكل نفسه — دائمًا HTTP 200 لحالات العمل المعروفة، وترمز
النتيجة في الجسم. رموز HTTP غير 2xx محجوزة للأعطال الحقيقية فقط.

```jsonc
// نجاح
{ "ok": true, "data": { ... }, "request_id": "a3f19c4e" }

// فشل عمل معروف
{ "ok": false, "code": "qr_mismatch", "message": "الرمز لا يخص عميل هذا الطلب",
  "request_id": "a3f19c4e" }
```

> **قرار مقصود**: في النظام الحالي كانت الأخطاء تعود كـ`non-2xx` فتبتلعها مكتبة
> العميل وتعرض «Edge Function returned a non-2xx status code». هنا: حالة العمل
> في الجسم دائمًا، والواجهة تقرأ `code` وتعرض رسالة مفهومة.

### الترويسات

| الترويسة | الاتجاه | الغرض |
|---|---|---|
| `X-Request-Id` | طلب | يولّده العميل؛ يُسجَّل ويُعاد ويُعرض في رسالة الخطأ |
| `Authorization: Bearer` | طلب | JWT الموظف — إلزامي لكل ما عدا `public-qr` والـwebhook |
| `X-Idempotency-Key` | طلب | للعمليات المالية والميدانية |
| `X-App-Version` | طلب | إصدار الواجهة — لرفض النسخ القديمة جدًا |

### رموز الأخطاء الموحّدة

| الرمز | المعنى |
|---|---|
| `invalid_input` | فشل التحقق من المدخلات |
| `invalid_qr` | الرمز غير موجود أو تالف |
| `revoked_qr` | الرمز أُبطل بإعادة إصدار |
| `inactive_customer` | العميل معطَّل أو محذوف |
| `inactive_property` | العقار معطَّل |
| `profile_incomplete` | الملف يحتاج استكمالًا أولًا |
| `otp_required` | لا تحقق صالح |
| `otp_invalid` | رمز خاطئ |
| `otp_expired` | انتهت الصلاحية |
| `otp_blocked` | تجاوز المحاولات أو الحد الزمني |
| `rate_limited` | تجاوز حد المعدل |
| `submission_expired` | رمز الإرسال منتهٍ |
| `submission_consumed` | رمز الإرسال مُستخدَم |
| `order_not_found` | الطلب غير موجود |
| `stale_state` | حالة الطلب تغيّرت — أعد التحميل |
| `invalid_transition` | انتقال غير مسموح |
| `qr_mismatch` | الرمز لا يخص عميل هذا الطلب |
| `payment_required` | الطلب غير مدفوع |
| `duplicate_invoice` | رقم الفاتورة مستخدم |
| `provider_error` | عطل عند مزود خارجي |
| `forbidden` | صلاحية غير كافية |
| `photo_required` | الصورة إلزامية ومفقودة |
| `unhanded_cash` | المندوب لم يسلّم نقد أيام سابقة — لا تحصيل جديد |
| `settlement_locked` | التسوية معتمدة ولا تقبل تعديلًا |
| `settlement_closed` | التسوية مُسلَّمة ولا تقبل تحصيلات جديدة |
| `proof_required` | طريقة التسليم تتطلب صورة إثبات |
| `proof_reused` | صورة الإثبات مستخدمة في تسوية سابقة |
| `self_verification` | لا يجوز اعتماد تسويتك أنت |
| `variance_needs_approval` | الفرق خارج حد السماح ويحتاج اعتماد `manager`+ |
| `photo_rejected` | الصورة رُفضت (حجم/نوع/بصمة) |
| `server_error` | عطل غير متوقع — مصحوب دائمًا بـ`request_id` |

---

## 2. `public-qr` — بلا JWT

**CORS**: `https://qr.myduby.com` فقط.
**حد المعدل**: 60 طلبًا/دقيقة لكل `ip_hash`.

### `POST /scan`

```jsonc
// طلب
{ "token": "3f2a...-uuid" }

// نجاح — ملف غير مكتمل
{ "ok": true, "data": {
    "scan_session_id": "…",
    "profile_status": "incomplete",
    "required_fields": ["full_name","phone","floor_number","apartment_number"]
}}

// نجاح — ملف مكتمل
{ "ok": true, "data": {
    "scan_session_id": "…",
    "profile_status": "complete",
    "phone_masked": "+968 ****23",
    "can_request_otp": true,
    "resend_available_in": 0
}}
```

**لا تُعاد أبدًا**: اسم العميل، الهاتف كاملًا، العقار، الطابق، رقم الشقة،
معرّف العميل.

الأخطاء: `invalid_qr`, `revoked_qr`, `inactive_customer`, `inactive_property`, `rate_limited`

### `POST /complete-profile`

```jsonc
// طلب
{ "scan_session_id": "…", "full_name": "…",
  "phone": "91234567",        // 8 أرقام أو +968XXXXXXXX
  "floor_number": "3", "apartment_number": "12" }

// نجاح
{ "ok": true, "data": { "profile_status": "incomplete", "next": "request_otp" } }
```

> أي `property_id` في الجسم **يُتجاهل صامتًا** ويُسجَّل في التدقيق كمحاولة تلاعب.
> الملف يبقى `incomplete` حتى نجاح OTP.

الأخطاء: `invalid_input`, `invalid_qr`, `rate_limited`

### `POST /request-otp`

```jsonc
{ "scan_session_id": "…" }
→ { "ok": true, "data": { "expires_in": 300, "resend_available_in": 60,
                          "attempts_remaining": 5 } }
```

الأخطاء: `profile_incomplete`, `rate_limited`, `otp_blocked`, `provider_error`

### `POST /verify-otp`

```jsonc
{ "scan_session_id": "…", "code": "123456" }
→ { "ok": true, "data": { "submission_token": "…", "expires_in": 900,
                          "next": "capture_photo" } }
```

الأخطاء: `otp_invalid` (مع `attempts_remaining`), `otp_expired`, `otp_blocked`

### `POST /photo-upload-url`

```jsonc
{ "submission_token": "…", "content_type": "image/jpeg", "byte_size": 842113 }
→ { "ok": true, "data": { "upload_url": "…", "storage_path": "staging/…jpg",
                          "expires_in": 300 } }
```

الرفع يذهب من المتصفح إلى Storage مباشرة — لا يمر بالوظيفة. هذا يتجنب حد حجم
الطلب على Edge Functions ويقلّل زمن الاستجابة.

### `POST /submit-order`

```jsonc
{ "submission_token": "…", "storage_path": "staging/…jpg",
  "byte_size": 842113, "sha256": "…" }
→ { "ok": true, "data": { "order_no": 1042, "status": "new",
                          "created_at": "2026-09-16T08:30:00Z" } }
```

إعادة الإرسال بنفس الرمز تُعيد **نفس الطلب**، لا طلبًا جديدًا.

الأخطاء: `submission_expired`, `submission_consumed`, `photo_rejected`

---

## 3. `staff-orders` — JWT إلزامي

**CORS**: `https://app.myduby.com` فقط.

### `POST /advance`

```jsonc
{ "order_id": "…", "expected_status": "picked_up" }
→ { "ok": true, "data": { "order": { "status": "processing", … } } }
```

`expected_status` يفرض فحصًا تفاؤليًا: إن كانت الحالة الفعلية مختلفة يعود
`stale_state` وتُعيد الواجهة التحميل. هذا يمنع تعارض موظفَين على نفس الطلب.

الأخطاء: `stale_state`, `invalid_transition`, `forbidden`, `order_not_found`

### `POST /field-step` — الاستلام والتسليم

أهم نقطة نهاية في النظام.

```jsonc
// طلب
{ "order_id": "…",
  "step": "pickup",              // pickup | delivery
  "qr_token": "3f2a…",           // UUID أو رابط QR كامل — تُطبَّع في الخادم
  "storage_path": "staging/…jpg",
  "byte_size": 742113,
  "sha256": "…",
  "latitude": 23.5880,           // اختياري
  "longitude": 58.3829 }

// نجاح
{ "ok": true, "data": { "order": {
    "id": "…", "status": "picked_up",
    "pickup_confirmed_at": "2026-09-16T09:12:44Z",
    "pickup_confirmed_by": "…"
}}}

// فشل
{ "ok": false, "code": "qr_mismatch",
  "message": "الرمز الممسوح لا يخص عميل هذا الطلب",
  "request_id": "a3f19c4e" }
```

**ضمانات العقد** — كل واحدة مشتقة من عطل حقيقي:

1. العملية ذرّية: تنجح كاملة أو لا أثر لها.
2. عند الفشل تُحذف الصورة المؤقتة تلقائيًا.
3. `ok: true` **لا تعود** إلا وسجل الطلب محفوظ فعلًا بالحالة الجديدة.
4. الطلب المُعاد في الاستجابة هو الحالة المحفوظة، لا حالة متوقعة.
5. `qr_token` يقبل UUID أو رابطًا كاملًا، ويُطبَّع في الخادم (قص، توحيد أحرف).
6. الواجهة **لا تستدعي** `refreshSession()` في هذا المسار.

الأخطاء: `qr_mismatch`, `payment_required`, `stale_state`, `invalid_transition`,
`photo_rejected`, `forbidden`, `order_not_found`

### `POST /cancel`

```jsonc
{ "order_id": "…", "reason": "العميل ألغى الطلب" }   // ≥ 3 أحرف
```

الأخطاء: `invalid_input`, `invalid_transition` (الطلب `completed`), `forbidden`

### `GET /photo-url?photo_id=…`

```jsonc
→ { "ok": true, "data": { "url": "https://…", "expires_in": 120 } }
```

الرابط الموقّع يصدر بعد فحص أن المستدعي موظف فعّال. الحاوية خاصة ولا رابط دائم.

---

## 4. `payments` — JWT إلزامي

### `POST /invoice`

```jsonc
{ "order_id": "…", "invoice_number": "INV-2026-0042", "amount": 4.500 }
→ { "ok": true, "data": {
      "order": { "status": "out_for_delivery", "payment_status": "unpaid" },
      "payment": { "checkout_url": "https://uatcheckout.thawani.om/pay/…" } } }
```

الأخطاء: `duplicate_invoice`, `invalid_input`, `invalid_transition`, `provider_error`

عند `provider_error`: لا فاتورة تُحفظ ولا حالة تتغير — المعاملة كاملة تتراجع.

### `POST /verify` — استعلام يدوي

```jsonc
{ "order_id": "…" }
→ { "ok": true, "data": { "payment_status": "paid", "verified_at": "…" } }
```

### `POST /cash`

يسجّله **المندوب** الذي استلم المبلغ. متاح لكل الأدوار من `courier` فأعلى.

```jsonc
{ "order_id": "…" }
→ { "ok": true, "data": {
      "order": { "payment_status": "paid", "payment_method": "cash_on_delivery" },
      "settlement": { "id": "…", "business_date": "2026-09-16",
                      "expected_amount": 18.750, "collections_count": 4 } } }
```

الاستجابة تعيد حالة التسوية بعد القيد — فيرى المندوب فورًا كم أصبح بذمته اليوم.

الأخطاء: `unhanded_cash` (نقد غير مسلَّم تجاوز الحد), `invalid_transition`,
`order_not_found`

### `POST /cash/reverse`

```jsonc
{ "collection_id": "…", "reason": "خطأ في المبلغ" }
```

متاح للمندوب نفسه في نفس اليوم، ولـ`operator`+ دائمًا — **قبل اعتماد التسوية فقط**.

الأخطاء: `settlement_locked`, `forbidden`, `invalid_input`

### `POST /reverse`

```jsonc
{ "order_id": "…", "reason": "خطأ في التسجيل" }
```

`admin` فقط. يُرفض إذا كان `payment_method = 'thawani'` مع تأكيد من المزود.

---

## 5. `settlements` — JWT إلزامي

### `GET /settlements/mine`

تسويات المستدعي. متاح لكل الأدوار.

```jsonc
→ { "ok": true, "data": { "settlements": [{
      "id": "…", "business_date": "2026-09-16", "state": "open",
      "expected_amount": 18.750, "collections_count": 4,
      "declared_amount": null, "confirmed_amount": null, "variance": null,
      "handover_at": null, "blocked": false }]}}
```

### `POST /settlements/:id/handover`

المندوب يسلّم النقد ويوثّق ذلك. صاحب التسوية فقط.

```jsonc
// طلب
{ "declared_amount": 18.750,
  "handover_method": "bank_deposit",        // bank_deposit | transfer | office_handover | safe_drop
  "handover_reference": "DEP-88421",        // اختياري
  "proof": { "storage_path": "staging/…jpg", "byte_size": 412880, "sha256": "…" },
  "note": "" }

// نجاح
{ "ok": true, "data": { "settlement": {
    "state": "handed_over", "expected_amount": 18.750,
    "declared_amount": 18.750, "handover_at": "2026-09-16T19:40:11Z" }}}
```

**ضمانات العقد**:

1. `bank_deposit` و`transfer` تتطلبان `proof` ← وإلا `proof_required`.
2. بصمة `sha256` مستخدمة في تسوية سابقة ← `proof_reused`. هذا يمنع إعادة استخدام
   إيصال إيداع قديم.
3. بعد النجاح **لا تُقبل تحصيلات جديدة** في هذه التسوية — تحصيل لاحق يفتح تسوية
   اليوم التالي.
4. الصورة تُنقل من المسار المؤقت إلى النهائي فقط عند نجاح العملية.

الأخطاء: `forbidden`, `settlement_locked`, `proof_required`, `proof_reused`,
`invalid_input`

### `GET /settlements`

قائمة التسويات مع تصفية. `operator` فأعلى.

```
?business_date=2026-09-16&state=handed_over&courier_id=…&overdue=true
```

`overdue=true` تُرجع ما تجاوز `cash.verify_sla_hours` بلا اعتماد.

### `GET /settlements/:id`

تفاصيل تسوية واحدة، مع **رابط موقّع لصورة الإثبات** — وهو ما يمكّن الاعتماد عن بُعد.

```jsonc
→ { "ok": true, "data": { "settlement": {
      "id": "…", "courier": { "id": "…", "name": "محمد" },
      "business_date": "2026-09-16", "state": "handed_over",
      "expected_amount": 18.750, "declared_amount": 18.750,
      "collections": [{ "order_no": 1042, "amount": 4.500, "collected_at": "…" }],
      "handover_method": "bank_deposit", "handover_reference": "DEP-88421",
      "handover_at": "2026-09-16T19:40:11Z",
      "proof_url": "https://…", "proof_url_expires_in": 120,
      "hours_since_handover": 14.2 }}}
```

### `POST /settlements/:id/verify`

`operator` فأعلى يعتمد **عن بُعد** بمطابقة الإثبات — لا بعدّ حضوري.

```jsonc
// طلب
{ "confirmed_amount": 18.750, "variance_reason": "" }

// نجاح: الفرق صفر أو ضمن السماح
{ "ok": true, "data": { "settlement": {
    "state": "verified", "expected_amount": 18.750,
    "confirmed_amount": 18.750, "variance": 0.000,
    "verified_by": "…", "verified_at": "…" }}}

// الفرق خارج السماح
{ "ok": true, "data": { "settlement": { "state": "disputed", "variance": -3.500 },
                        "next": "requires_manager_approval" } }
```

**ضمانات العقد**:

1. `verified_by = courier_id` ← `self_verification` مرفوض في قاعدة البيانات،
   **بلا استثناء لأي دور بما فيه `admin`**.
2. `expected_amount` لا يُقبل من الطلب — يُحسب من `cash_collections`.
3. `variance` عمود محسوب، لا يُرسل ولا يُكتب.
4. فرق غير صفري بلا سبب ← `invalid_input`.
5. التسوية `verified` مقفلة — أي تعديل عدا المطابقة البنكية ← `settlement_locked`.

الأخطاء: `self_verification`, `settlement_locked`, `forbidden`, `invalid_input`

### `POST /settlements/:id/approve-variance`

`manager` فأعلى، للتسويات `disputed`.

```jsonc
{ "reason": "الفرق مطابق لكشف البنك — خصم من مستحقات المندوب" }
→ { "ok": true, "data": { "settlement": { "state": "verified", "approved_by": "…" }}}
```

لا يجوز للمعتمِد أن يكون المندوب نفسه — مفروض بقيد.

### `POST /settlements/:id/match-bank`

وسم المطابقة البنكية بعد ورود كشف الحساب. `operator` فأعلى.
**الاستثناء الوحيد المسموح على تسوية معتمدة.**

```jsonc
{ "bank_reference": "TXN-2026-09-17-0042" }
→ { "ok": true, "data": { "settlement": { "bank_matched_at": "…" }}}
```

### `GET /settlements/unmatched`

إيداعات معتمدة بلا مرجع بنكي. `operator` فأعلى.

### `GET /settlements/pending-cash`

النقد **غير المسلَّم** لكل مندوب حسب العمر. `operator` فأعلى.

```jsonc
→ { "ok": true, "data": { "couriers": [{
      "courier_id": "…", "name": "…",
      "open_settlements": 1, "oldest_business_date": "2026-09-15",
      "unhanded_amount": 18.750, "days_unhanded": 1, "blocked": false }]}}
```

`blocked: true` يعني تجاوز `cash.max_unhanded_days`. التسويات المسلَّمة
بانتظار الاعتماد **لا تدخل هنا ولا تسبب حجبًا** — التأخير على المدقّق لا المندوب.

---

## 6. `payments-webhook` — بلا JWT، بتوقيع

### `POST /thawani`

1. التحقق من توقيع الطلب (HMAC بسر مشترك).
2. رفض أي طلب بلا توقيع صالح بـ`401` **قبل** قراءة الجسم.
3. `fn_apply_payment_webhook()` — تطبيق مُعاد الأمان (idempotent).
4. الإعادة دائمًا `200` بعد المعالجة لمنع إعادة الإرسال اللانهائية.
5. كل استدعاء يُسجَّل في `payment_events` حتى لو لم يغيّر شيئًا.

---

## 7. `admin` — JWT إلزامي، دور `admin`

| النقطة | الوصف |
|---|---|
| `GET /staff` | قائمة الموظفين |
| `POST /staff` | دعوة موظف جديد (بريد + دور) |
| `PATCH /staff/:id` | تعديل الدور أو التفعيل |
| `GET /settings` | إعدادات النظام |
| `PUT /settings/statuses/:status` | تفعيل الإشعار ونصّه |
| `PUT /settings/:key` | قيمة إعداد عام |
| `GET /audit` | سجل التدقيق مع تصفية وترقيم |

---

## 8. `notifications` — داخلية

تُستدعى من `pg_cron` كل دقيقة. لا يمكن استدعاؤها من الإنترنت.

```
1. SELECT … FOR UPDATE SKIP LOCKED  (دفعة 50)
2. لكل عنصر: إرسال عبر WhatsAppBridgeProvider
3. نجاح ← sent + provider_msg_id
   فشل  ← failed + next_attempt_at بتراجع أسّي
4. بعد 5 محاولات ← dead + تنبيه
```

---

## 9. القراءة المباشرة من PostgREST

الواجهة تقرأ الجداول مباشرة عبر عميل Supabase (محكومة بـRLS) ولا تمر بوظائف.
هذا يقلّل الاستدعاءات ويستفيد من الفلترة والترقيم الجاهزين.

**الاستعلامات المتوقعة**:

```sql
-- الطلبات النشطة لعقار (يخدمه orders_active_idx)
select * from orders
 where property_id = $1 and status not in ('completed','cancelled')
 order by created_at desc;

-- الأرشيف مع ترقيم
select * from orders
 where status in ('completed','cancelled')
 order by status_changed_at desc limit 50 offset $1;

-- خط زمني للطلب
select * from order_status_history where order_id = $1 order by changed_at;
```

**الكتابة من الواجهة ممنوعة تمامًا** — لا سياسة `insert`/`update`/`delete` لأي
دور. كل تعديل يمر بوظيفة تتحقق من الصلاحية وتكتب التدقيق.

---

## 10. الإصدارات والتوافق

- كل وظيفة تقرأ `X-App-Version`. إن كان أقدم من الحد الأدنى المدعوم:
  `{"ok":false,"code":"app_outdated"}` والواجهة تعرض شاشة تحديث إجباري.
- تغييرات العقود تتبع الإضافة لا الاستبدال: حقل جديد اختياري لا يكسر نسخة قديمة.
- تغيير كاسر ← نقطة نهاية جديدة `/v2/…` وإبقاء القديمة دورة إصدار واحدة.
