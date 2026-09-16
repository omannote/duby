# 13 — ترحيل البيانات

## 1. حجم العمل

بيانات الإنتاج الحالية كما ظهرت في التدقيق الأخير:

| الكيان | العدد | ملاحظات |
|---|---|---|
| العقارات | قليل | نقل مباشر |
| العملاء | عشرات | بعضهم غير مكتمل، وواحد بلا عقار |
| الطلبات | 5 | أربعة `delivered` بالمعنى القديم، وواحد بالمعنى الجديد |
| تحديات OTP | 13 | 6 منها فاشلة |
| إشعارات الحالة | 18 | كلها مُرسلة |
| صور الطلبات | قليلة | في حاوية خاصة |

الحجم صغير — وهذه فرصة. الترحيل ليس تحديًا تقنيًا بقدر ما هو فرصة **لتصحيح
الدلالة** قبل أن تكبر البيانات.

---

## 2. التحدي الأساسي: معنى `delivered`

الحالة `delivered` استُخدمت بمعنيين مختلفين في فترتين مختلفتين، ويميّز بينهما
حقل `workflow_version`:

| النسخة | ما كانت تعنيه `delivered` | الترحيل |
|---|---|---|
| `workflow_version = 1` | **التسليم النهائي تم** | ← `completed` |
| `workflow_version = 2` | خرج للتوصيل، لم يُسلَّم بعد | ← `out_for_delivery` |

### قاعدة التمييز

```sql
case
  when workflow_version = 1 and status = 'delivered'
    then 'completed'
  when workflow_version = 2 and status = 'delivered'
       and delivery_photo_path is null
    then 'out_for_delivery'
  when workflow_version = 2 and status = 'delivered'
       and delivery_photo_path is not null
    then 'completed'
end
```

وجود صورة التسليم هو الدليل الحاسم: من التقط صورة تسليم فقد سلّم فعلًا.

### خريطة الحالات الكاملة

| الحالة القديمة | النسخة | الحالة الجديدة | ملاحظة |
|---|---|---|---|
| `new` | أي | `new` | مباشر |
| `confirmed` | أي | `confirmed` | مباشر |
| `picked_up` | أي | `picked_up` | مباشر |
| `processing` | أي | `processing` | مباشر |
| `ready` | 2 | `ready` | مباشر |
| `completed` | 1 | `out_for_delivery` | في النسخة 1 كان يعني «جاهز مع فاتورة» |
| `completed` | 2 | `completed` | مباشر |
| `delivered` | 1 | `completed` | تسليم نهائي |
| `delivered` | 2 | حسب الصورة | انظر القاعدة أعلاه |
| `cancelled` | أي | `cancelled` | مباشر |

**بعد الترحيل يُحذف `workflow_version` نهائيًا** — لا نسخة مسار ثانية في النظام
الجديد (ADR-010).

---

## 3. ترتيب الترحيل

يتبع اعتماديات المفاتيح الأجنبية:

```
1. staff             ← من staff_profiles + auth.users (مع إعادة تصنيف الأدوار — D0)
2. properties
3. customers         ← مع تعيين عقار للعميل اليتيم
4. customer_qr_tokens ← من customers.qr_token (رمز فعّال واحد لكل عميل)
5. scan_events
6. otp_challenges    ← السجلات الحديثة فقط (90 يومًا)
7. orders            ← مع تحويل الحالات
8. order_photos      ← من حقول المسارات في orders
9. order_status_history ← ما يمكن استنتاجه من الطوابع الزمنية
10. payments + payment_events
10ب. cash_settlements + cash_collections ← من الطلبات المدفوعة نقدًا
11. order_status_settings
12. صور Storage       ← نسخ بين الحاويات
```

---

## 4. حالات تحتاج قرارًا منك

| # | الحالة | الخيارات | التوصية |
|---|---|---|---|
| D0 | **دور كل موظف حالي** | الكل `operator` / تصنيفهم حسب عملهم الفعلي | تصنيفهم يدويًا: من يعمل ميدانيًا ويستلم النقد ← `courier`؛ من يدقّق ويتابع ← `operator`. **يجب وجود `operator` واحد على الأقل ليس مندوبًا** وإلا تعذّر اعتماد أي تسوية |
| D1 | عميل بلا عقار | تعيين عقار افتراضي / إنشاء عقار «غير محدد» / تعطيله | تعيين العقار الصحيح يدويًا — عميل واحد فقط |
| D2 | عملاء `incomplete` قدامى | ترحيلهم كما هم / تعطيلهم | ترحيلهم — رموزهم قد تكون مطبوعة وموزّعة |
| D3 | تحديات OTP الفاشلة الست | ترحيلها للتحليل / تجاهلها | تجاهلها — بيانات اختبار على الأرجح |
| D4 | الطلب `delivered` المعلّق | `out_for_delivery` / إغلاقه يدويًا | مراجعته معك: هل سُلِّم فعلًا؟ |
| D5 | `order_status_history` | استنتاجها من الطوابع / بدء السجل من الترحيل | استنتاج ما يمكن + سطر «مُرحَّل» صريح |
| D6 | حاوية `qr-public` القديمة | حذفها / أرشفتها | حذفها بعد نسخة احتياطية |

كل قرار يُوثَّق في سكربت الترحيل كتعليق مع تاريخ الاعتماد.

---

## 5. السكربتات

```
scripts/migration/
├── 00-audit-source.sql          تقرير كامل عن الحالة الحالية
├── 01-export-source.ts          تصدير إلى JSON مع تدقيق
├── 02-transform.ts              التحويل + قواعد الحالات
├── 03-validate-transform.ts     فحوص ما قبل التحميل
├── 04-load-target.ts            التحميل بترتيب الاعتماديات
├── 05-migrate-storage.ts        نسخ الصور
├── 06-verify.sql                مطابقة المصدر بالهدف
└── 07-rollback.sql              إلغاء كامل للترحيل
```

### `00-audit-source.sql` — يُنفَّذ في المرحلة 1

```sql
-- توزيع الحالات × النسخة
select workflow_version, status, count(*),
       count(*) filter (where delivery_photo_path is not null) as with_delivery_photo
  from orders group by 1,2 order by 1,2;

-- الشذوذ
select 'عميل بلا عقار' as issue, count(*) from customers where property_id is null
union all
select 'طلب بلا صورة استلام', count(*) from orders
 where status not in ('new','confirmed','cancelled') and pickup_photo_path is null
union all
select 'مكتمل غير مدفوع', count(*) from orders
 where status = 'completed' and payment_status <> 'paid'
union all
select 'رقم فاتورة مكرر', count(*) from (
  select invoice_number from orders where invoice_number is not null
   group by 1 having count(*) > 1) t
union all
select 'هاتف مكرر بين الفعّالين', count(*) from (
  select phone from customers where is_active and phone is not null
   group by 1 having count(*) > 1) t;
```

> **مهم**: يُنفَّذ في **المرحلة 1** لا المرحلة 7. معرفة حجم الشذوذ مبكرًا تحدد
> قواعد الترحيل وتمنع مفاجأة قبل الإطلاق بأيام.

### `06-verify.sql` — بوابة القبول

```sql
-- العدد
select 'customers', (select count(*) from source.customers),
                    (select count(*) from public.customers);
select 'orders',    (select count(*) from source.orders),
                    (select count(*) from public.orders);

-- المجاميع المالية
select 'invoice_total', (select sum(invoice_amount) from source.orders),
                        (select sum(invoice_amount) from public.orders);

-- سلامة العلاقات
select count(*) as orphan_orders from orders o
  left join customers c on c.id = o.customer_id where c.id is null;

-- كل رمز QR قديم له مقابل فعّال
select count(*) as missing_tokens from source.customers sc
  where not exists (select 1 from customer_qr_tokens t
                     where t.token = sc.qr_token and t.revoked_at is null);

-- لا حالة غير معروفة
select status, count(*) from orders
 where status not in ('new','confirmed','picked_up','processing',
                      'ready','out_for_delivery','completed','cancelled')
 group by 1;
```

الترحيل لا يُعتمد إلا إذا كانت كل الأعداد متطابقة والشذوذ صفرًا.

---

## 5ب. ترحيل النقد التاريخي

الطلبات القديمة المدفوعة `cash_on_delivery` لا تملك تحصيلات ولا تسويات — الجدولان
جديدان. الخيار الموصى به:

```sql
-- تسوية افتتاحية واحدة لكل مندوب، مغلقة ومعتمدة، بفرق صفر
insert into cash_settlements (courier_id, business_date, state,
                              expected_amount, declared_amount, counted_amount,
                              verified_by, verified_at, notes)
select paid_recorded_by, '<تاريخ الترحيل>'::date, 'verified',
       sum(invoice_amount), sum(invoice_amount), sum(invoice_amount),
       '<معرّف المدير>', now(),
       'تسوية افتتاحية — نقد مُحصَّل قبل تفعيل نظام التسوية، سُوّي خارج النظام'
  from orders
 where payment_method = 'cash_on_delivery' and payment_status = 'paid'
 group by paid_recorded_by;
```

ثم تُربط بها `cash_collections` المقابلة.

**لماذا مغلقة ومعتمدة**: النقد القديم سُلِّم فعلًا خارج النظام. لو رُحِّل مفتوحًا
لبدأ كل مندوب بذمة وهمية، ولحُجب عن التحصيل فور الإطلاق.

> استثناء لقاعدة «لا اعتماد ذاتي»: هذه التسويات يعتمدها المدير في سياق الترحيل،
> ويجب ألا يكون هو نفسه المندوب في أي منها. إن كان — يعتمدها `admin` آخر.

---

## 6. توافق روابط QR

الرموز المطبوعة والملصقة في الشقق تشير إلى:

```
https://myduby.com/qr/?token={uuid}
```

النظام الجديد يستخدم:

```
https://qr.myduby.com/?t={uuid}
```

### الحل: تحويل دائم، بلا إعادة طباعة

في GoDaddy — المسار القديم يبقى، ويحوّل:

```apache
RewriteEngine On
RewriteCond %{QUERY_STRING} (?:^|&)token=([^&]+)
RewriteRule ^qr/?$ https://qr.myduby.com/?t=%1 [R=301,L,QSD]
```

وفي `qr.myduby.com` يُقبل الوسيطان `t` و`token` معًا لضمان التوافق.

> هذه نقطة حرجة: **UUID الرمز نفسه يُنقل كما هو** إلى `customer_qr_tokens`.
> لو تغيّر لأصبحت كل الرموز المطبوعة عديمة الفائدة.

---

## 7. خطة الإطلاق

### أسلوب: تشغيل متوازٍ ثم تحويل

```
يوم -14  تجربة ترحيل كاملة على نسخة من الإنتاج → قياس الزمن والشذوذ
يوم -7   تدريب الموظفين على النظام الجديد ببيانات مُرحَّلة
يوم -3   تجميد التغييرات على النظام القديم (إصلاحات أمنية فقط)
يوم -1   نسخة احتياطية كاملة + ترحيل نهائي + تحقق
يوم  0   تفعيل التحويل + النظام الجديد حيّ
         النظام القديم يبقى للقراءة فقط
يوم +1..5 تشغيل متوازٍ: الجديد للعمل، القديم للمراجعة عند الشك
يوم +7   إيقاف القديم
يوم +14  حذف موارد القديم بعد نسخة احتياطية أرشيفية
```

### نافذة التحويل

يُنفَّذ في أقل أوقات النشاط (ليلًا). الزمن المقدّر:

| الخطوة | الزمن |
|---|---|
| نسخة احتياطية | 5 دقائق |
| تصدير | 2 دقيقة |
| تحويل وتحقق | 3 دقائق |
| تحميل | 5 دقائق |
| ترحيل الصور | 10 دقائق |
| تحقق نهائي | 5 دقائق |
| تفعيل التحويل | 2 دقيقة |
| **الإجمالي** | **≈ 35 دقيقة** |

توقف الخدمة الفعلي: أقل من 15 دقيقة (فقط عند تفعيل التحويل).

---

## 8. خطة التراجع

### متى نتراجع

| الشرط | القرار |
|---|---|
| فقد بيانات مؤكد | تراجع فوري |
| مسار العميل لا يعمل > 30 دقيقة | تراجع فوري |
| مسار الدفع معطّل | تراجع فوري |
| عطل في واجهة الموظفين مع بديل يدوي | إصلاح دون تراجع |
| بطء أو عيب تجميلي | إصلاح دون تراجع |

### الإجراء

```
1. إلغاء تحويل الروابط في GoDaddy       (دقيقتان)
2. إعادة تفعيل النظام القديم للكتابة      (دقيقة)
3. إشعار الموظفين                        (فوري)
4. نقل ما أُنشئ في الجديد إلى القديم يدويًا (حسب العدد)
5. تحليل السبب قبل أي محاولة ثانية
```

**شرط**: النظام القديم يبقى قابلًا للتشغيل الكامل لمدة **14 يومًا** بعد الإطلاق.
لا حذف لأي مورد قبل انقضائها.

---

## 9. تدريب الموظفين

| الجلسة | المدة | المحتوى |
|---|---|---|
| 1 | 60 دقيقة | نظرة عامة، الفروق عن القديم، تسجيل الدخول، الطلبات |
| 2 | 60 دقيقة | الاستلام والتسليم الميداني — **تدريب عملي على أجهزتهم** |
| 3 | 45 دقيقة | الفوترة والدفع والإلغاء |
| 4 | 30 دقيقة | ماذا تفعل عند الخطأ، وكيف تبلّغ عنه بـ`request_id` |

### مواد مرافقة

- بطاقة مرجعية من صفحة واحدة لكل دور.
- فيديو قصير (3 دقائق) لمسار الاستلام والتسليم.
- قناة دعم مباشرة خلال الأسبوعين الأولين.

الجلسة الثانية على أجهزتهم الفعلية هي الأهم — فهي التي تكشف مشاكل الكاميرا
والأذونات قبل الإطلاق لا بعده.
