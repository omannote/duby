#!/usr/bin/env bash
# تشغيل الترحيل بالترتيب، بوقفة قبل الخطوة التي تكتب.
#
#   TARGET_DB_URL=… ./scripts/migration/run.sh
#
# المتغيّرات الاختيارية: SOURCE_DB_URL (لإرفاق المصدر أولًا)، SKIP_STORAGE=1.
set -euo pipefail

cd "$(dirname "$0")/../.."
TARGET_DB_URL="${TARGET_DB_URL:?رابط قاعدة الهدف مطلوب}"

run() {
  echo ""
  echo "══ $1"
  psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -X -q -f "scripts/migration/$2"
}

if [[ -n "${SOURCE_DB_URL:-}" ]]; then
  ./scripts/migration/attach-source.sh "$SOURCE_DB_URL" "$TARGET_DB_URL"
fi

run "محوّل المصدر" 01-source-adapter.sql
run "جداول القرارات" decisions.sql
run "تدقيق المصدر" 00-audit-source.sql
run "الفحص المسبق" 02-preflight.sql

# الوقفة الوحيدة: ما قبلها قراءة، وما بعدها كتابة لا رجعة عنها إلا بـ06
echo ""
read -r -p "اجتاز الفحص المسبق. أتابع إلى التحميل؟ اكتب «نعم»: " answer
[[ "$answer" == "نعم" ]] || { echo "أُلغي."; exit 1; }

run "التحويل والتحميل" 03-transform-load.sql

if [[ "${SKIP_STORAGE:-0}" != "1" ]]; then
  echo ""
  echo "══ نقل الصور"
  TARGET_DB_URL="$TARGET_DB_URL" node scripts/migration/04-migrate-storage.mjs
fi

run "التحقق" 05-verify.sql

echo ""
echo "✓ اكتمل الترحيل واجتاز التحقق."
echo "  للتراجع قبل الإطلاق: psql \"\$TARGET_DB_URL\" -f scripts/migration/06-rollback.sql"
