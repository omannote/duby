# دوبي — نظام طلبات الغسيل عبر QR

نظام إدارة طلبات **دوبي للغسيل السريع والجاف**. كل عميل له رمز QR دائم في شقته،
ومسحه يُنشئ طلبًا جديدًا. الاستلام والتسليم يتمّان بمسح رمز العميل مع صورة في
الموقع.

**الحالة**: المرحلة صفر — التأسيس. الهيكل وخط النشر جاهزان؛ منطق النطاق يبدأ
في المرحلة الأولى.

## البنية

```
apps/staff/        لوحة الموظفين — React + Vite (PWA لاحقًا)
apps/customer/     صفحة العميل العامة — حزمة منفصلة خفيفة
packages/shared/   الأنواع والمخططات ورموز الأخطاء وآلة الحالات
supabase/          الهجرات ووظائف Edge والبيانات البذرية
tests/db/          pgTAP — القيود والسياسات
tests/e2e/         Playwright — Chromium و WebKit
scripts/           فحص الترويسات، توليد الأنواع، تشغيل اختبارات القاعدة
```

## البدء

```bash
pnpm install && cp .env.example .env.local && supabase start && pnpm dev
```

التفاصيل والقواعد في [`CONTRIBUTING.md`](CONTRIBUTING.md).

## التوثيق

| المستند                                         | المحتوى                                   |
| ----------------------------------------------- | ----------------------------------------- |
| [تحليل النظام القائم](docs/system-analysis.md)  | المعمارية، الثغرات، تحليل الأسباب الجذرية |
| [خطة البناء](docs/plan/00-index.md)             | 14 مستندًا، 7 مراحل                       |
| [إعداد المرحلة صفر](docs/plan/phase-0-setup.md) | ما يتطلب حساباتك                          |

### خطة البناء

| #   | المستند                                                     |     | #   | المستند                                          |
| --- | ----------------------------------------------------------- | --- | --- | ------------------------------------------------ |
| 01  | [النطاق والمتطلبات](docs/plan/01-scope-and-requirements.md) |     | 08  | [التكاملات](docs/plan/08-integrations.md)        |
| 02  | [المعمارية](docs/plan/02-architecture.md)                   |     | 09  | [الاختبار](docs/plan/09-testing.md)              |
| 03  | [نموذج البيانات](docs/plan/03-data-model.md)                |     | 10  | [البنية والنشر](docs/plan/10-devops.md)          |
| 04  | [تدفقات النطاق](docs/plan/04-domain-flows.md)               |     | 11  | [قابلية الملاحظة](docs/plan/11-observability.md) |
| 05  | [عقود الواجهات](docs/plan/05-api-contracts.md)              |     | 12  | [خارطة الطريق](docs/plan/12-roadmap.md)          |
| 06  | [الأمن والصلاحيات](docs/plan/06-security.md)                |     | 13  | [ترحيل البيانات](docs/plan/13-migration.md)      |
| 07  | [الواجهات](docs/plan/07-frontend.md)                        |     | 14  | [دليل التشغيل](docs/plan/14-runbook.md)          |

## مراجع

- [`docs/chatgpt-transcript.md`](docs/chatgpt-transcript.md) — المحادثة التي بُني فيها النظام السابق
- [`docs/laravel-rebuild-brief.md`](docs/laravel-rebuild-brief.md) — أرشيف: خيار Laravel (مستبعد)
