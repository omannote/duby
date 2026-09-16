# 10 — البنية والنشر

> هذا المستند هو أهم مستند في الخطة من حيث العائد. غياب ما فيه هو ما حوّل أعطالًا
> بسيطة في النظام الحالي إلى جولات تشخيص طويلة.

---

## 1. بنية المستودع

```
duby/
├── apps/
│   ├── staff/                    تطبيق الموظفين PWA
│   │   ├── src/
│   │   ├── public/_headers        ← CSP وترويسات الأمن (تُنشر مع الموقع)
│   │   └── vite.config.ts
│   └── customer/                 صفحة العميل
│       ├── src/
│       └── public/_headers
├── packages/
│   ├── shared/
│   │   ├── src/db.ts              ← مولَّد من المخطط، لا يُحرَّر يدويًا
│   │   ├── src/schemas.ts         مخططات Zod (واجهة + خادم)
│   │   ├── src/errors.ts          رموز الأخطاء الموحّدة
│   │   └── src/providers/         واجهات المزودين المجرّدة
│   └── ui/                       مكوّنات مشتركة
├── supabase/
│   ├── config.toml
│   ├── migrations/               NNNN_description.sql — للأمام فقط
│   ├── functions/
│   │   ├── _shared/
│   │   ├── public-qr/
│   │   ├── staff-orders/
│   │   ├── payments/
│   │   ├── payments-webhook/
│   │   ├── notifications/
│   │   └── admin/
│   └── seed/
├── tests/
│   ├── db/                       pgTAP
│   ├── integration/
│   └── e2e/                      Playwright
├── docs/
├── scripts/
└── .github/workflows/
```

**المبدأ**: كل ما يعمل في الإنتاج موجود هنا. لا ملف يُبنى في مكان آخر ويُرفع
يدويًا. لا وظيفة تُحرَّر في لوحة Supabase. لا SQL يُنفَّذ من محرر الاستعلامات.

---

## 2. البيئات

| | تطوير محلي | `staging` | الإنتاج |
|---|---|---|---|
| Supabase | `supabase start` | مشروع مستقل | مشروع مستقل |
| الواجهات | `vite dev` | معاينة Cloudflare | `app/qr.myduby.com` |
| البيانات | بذرية | مجهولة الهوية | حقيقية |
| ثواني | مزيّف | UAT | Live |
| واتساب | مزيّف | جسر اختبار | جسر إنتاج |
| من ينشر | المطور | دمج في `main` | وسم إصدار |

**قاعدة صارمة**: لا تشخيص على الإنتاج. أي عطل يُعاد إنتاجه على `staging` أولًا.
النظام الحالي شخّص كل شيء على الإنتاج واستخدم `ROLLBACK` كبديل — وهو حل ذكي
لمشكلة ما كان يجب أن توجد.

---

## 3. الهجرات

### القواعد

1. **للأمام فقط** — لا تراجع تلقائي. التراجع هجرة جديدة.
2. اسم مرقّم: `0042_add_delivery_photo_constraint.sql`.
3. كل هجرة **قابلة لإعادة التشغيل** (`if not exists`, `create or replace`).
4. كل هجرة تمر على `staging` قبل الإنتاج، بلا استثناء.
5. كل هجرة تغيّر قيدًا **يجب** أن يرافقها اختبار pgTAP في نفس الالتزام.
6. الهجرات المدمِّرة (حذف عمود/جدول) تمر بثلاث مراحل: إيقاف الاستخدام ← دورة
   إصدار ← حذف.

### نمط التغيير التوسعي

```
1. إضافة الجديد (nullable أو بقيمة افتراضية)
2. ملء البيانات القديمة
3. نشر الكود الذي يكتب في القديم والجديد معًا
4. نشر الكود الذي يقرأ من الجديد
5. إضافة NOT NULL أو القيد
6. حذف القديم بعد دورة إصدار
```

هذا يمنع ما حدث في النظام الحالي: هجرة حالات على الإنتاج فشلت في منتصفها لأن
PostgreSQL لا يسمح بإعادة تسمية وسيط دالة عبر `CREATE OR REPLACE`.

### قبل كل هجرة على الإنتاج

```bash
# 1. نسخة احتياطية موسومة
supabase db dump --project-ref $PROD > backups/pre-migration-$(date +%F-%H%M).sql

# 2. تطبيق
supabase db push --project-ref $PROD

# 3. تحقق بعد التطبيق
psql $PROD_URL -f scripts/verify-schema.sql
```

---

## 4. CI/CD

### `.github/workflows/ci.yml` — على كل PR

```yaml
jobs:
  quality:
    steps:
      - pnpm install --frozen-lockfile
      - pnpm typecheck
      - pnpm lint
      - pnpm test:unit
      - supabase start
      - supabase db reset            # كل الهجرات من الصفر
      - pnpm test:db                 # pgTAP
      - pnpm test:integration
      - pnpm build
      - pnpm size-limit
      - pnpm test:e2e
      - gitleaks detect
      - pnpm audit --audit-level=high
      - pnpm gen:types && git diff --exit-code   # الأنواع متزامنة مع المخطط
```

آخر خطوة مهمة: تفشل إن غيّر أحد المخطط دون تحديث الأنواع المولَّدة — فيستحيل
أن تتباعد الواجهة عن قاعدة البيانات.

### `deploy-staging.yml` — على الدمج في `main`

```yaml
jobs:
  deploy:
    environment: staging
    steps:
      - supabase db push --project-ref ${{ secrets.STAGING_REF }}
      - supabase functions deploy --project-ref ${{ secrets.STAGING_REF }}
      - pnpm build && wrangler pages deploy
      - pnpm test:smoke:staging
      - node scripts/verify-headers.js https://staging.myduby.com
```

### `deploy-production.yml` — على وسم `v*.*.*`

```yaml
jobs:
  deploy:
    environment: production          # يتطلب موافقة يدوية
    steps:
      - node scripts/assert-staging-green.js
      - supabase db dump > backup-pre-deploy.sql
      - supabase db push --project-ref ${{ secrets.PROD_REF }}
      - supabase functions deploy --project-ref ${{ secrets.PROD_REF }}
      - pnpm build && wrangler pages deploy --branch main
      - pnpm test:smoke:production
      - node scripts/verify-headers.js https://app.myduby.com
      - node scripts/notify-release.js
```

### التراجع

| الطبقة | الآلية | الزمن |
|---|---|---|
| الواجهات | Cloudflare Pages ← نشرة سابقة | < 1 دقيقة |
| الوظائف | إعادة نشر من الوسم السابق | < 3 دقائق |
| المخطط | هجرة تصحيحية للأمام | حسب التغيير |

**قاعدة**: لا تُنشر هجرة كاسرة مع نشرة واجهة في وسم واحد. المخطط أولًا (متوافق
مع النسختين)، ثم الواجهة في وسم تالٍ. هذا يجعل تراجع الواجهة آمنًا دائمًا.

---

## 5. الاستضافة والنطاقات

| النطاق | الوجهة | الغرض |
|---|---|---|
| `app.myduby.com` | Cloudflare Pages | تطبيق الموظفين |
| `qr.myduby.com` | Cloudflare Pages | صفحة العميل |
| `myduby.com` | GoDaddy (كما هو) | الموقع التعريفي |
| `myduby.com/whatsapp` | GoDaddy (كما هو) | جسر واتساب |

الترويسات في `public/_headers` داخل المستودع ← تُراجَع كأي كود، وتُتحقَّق آليًا
بعد كل نشر. لا تعديلات `.htaccess` تُكتشف آثارها بعد ثلاث جولات تشخيص.

### توافق الروابط القديمة

رموز QR المطبوعة تشير إلى `myduby.com/qr/?token=…`. يُضاف تحويل دائم:

```
myduby.com/qr/*  →  qr.myduby.com/?$1   (301)
```

فتبقى كل الرموز المطبوعة صالحة بلا إعادة طباعة.

---

## 6. النسخ الاحتياطي والاستعادة

| ما | التكرار | الاحتفاظ | التخزين |
|---|---|---|---|
| قاعدة البيانات (Supabase تلقائي) | يومي | 7 أيام | Supabase |
| تفريغ منطقي (مهمة مجدولة) | يومي | 30 يومًا | تخزين خارجي |
| صور Storage | أسبوعي | 30 يومًا | تخزين خارجي |
| قبل كل نشر إنتاج | لكل نشر | 10 نشرات | أداة CI |

**RPO** ≤ 24 ساعة · **RTO** ≤ 4 ساعات

### اختبار الاستعادة — فصلي وإلزامي

```
1. إنشاء مشروع Supabase مؤقت
2. استعادة آخر تفريغ
3. التحقق: عدد الطلبات، عدد العملاء، تكامل المفاتيح الأجنبية
4. تشغيل مجموعة pgTAP على القاعدة المستعادة
5. توثيق الزمن الفعلي
6. حذف المشروع المؤقت
```

نسخة احتياطية لم تُختبر استعادتها ليست نسخة احتياطية.

---

## 7. الإصدارات

`MAJOR.MINOR.PATCH` — `v1.4.2`

| الجزء | يزيد عند |
|---|---|
| MAJOR | تغيير كاسر في عقد أو مخطط |
| MINOR | ميزة جديدة متوافقة |
| PATCH | إصلاح عطل |

رقم الإصدار ظاهر في شاشة «المزيد» بالتطبيق، ويُرسل في `X-App-Version` مع كل
طلب. هذا يجعل سؤال «أي نسخة تعمل عليها؟» بلا معنى — النظام يعرف.

---

## 8. التطوير المحلي

```bash
git clone … && cd duby
pnpm install
cp .env.example .env.local
supabase start                 # PostgreSQL + Auth + Storage محليًا
supabase db reset              # الهجرات + البيانات البذرية
pnpm dev                       # كلا التطبيقين
pnpm test                      # كل الاختبارات
```

الهدف: **مطور جديد يشغّل النظام كاملًا بخمسة أوامر**، بلا وصول إلى الإنتاج
وبلا مفاتيح حقيقية. البيانات البذرية تنشئ: 3 عقارات، 12 عميلًا في حالات مختلفة،
20 طلبًا موزّعة على كل الحالات، 4 موظفين بالأدوار الأربعة، وتسويتان نقديتان
(واحدة مفتوحة وأخرى معتمدة بفرق).

---

## 9. التكلفة التقديرية الشهرية

| البند | التقدير |
|---|---|
| Supabase Pro (إنتاج) | 25 دولارًا |
| Supabase (staging) | مجاني |
| Cloudflare Pages | مجاني |
| GitHub Actions | ضمن المجاني |
| تخزين النسخ الاحتياطية | 1–3 دولارات |
| **الإجمالي** | **≈ 28 دولارًا شهريًا** |

عمولات ثواني وتكلفة رسائل واتساب خارج هذا الحساب (متغيرة حسب الحجم).
