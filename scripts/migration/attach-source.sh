#!/usr/bin/env bash
# استعادة تفريغ النظام القديم في مخطط `legacy` داخل قاعدة الهدف.
#
# كلا النظامين على PostgreSQL، فنقل المخطط كما هو أبسط وأدق من تصدير إلى JSON
# ثم استيراده: لا فقد أنواع، ولا طبقة تحويل إضافية تُخطئ.
#
#   ./scripts/migration/attach-source.sh "$SOURCE_DB_URL" "$TARGET_DB_URL"
set -euo pipefail

SOURCE_DB_URL="${1:?رابط قاعدة المصدر مطلوب}"
TARGET_DB_URL="${2:?رابط قاعدة الهدف مطلوب}"
DUMP_FILE="${DUMP_FILE:-/tmp/duby-legacy.sql}"

echo "→ تفريغ المصدر (بيانات وبنية، بلا مالكين ولا صلاحيات)…"
pg_dump "$SOURCE_DB_URL" \
  --schema=public \
  --no-owner --no-privileges --no-publications --no-subscriptions \
  --exclude-table='auth.*' \
  > "$DUMP_FILE"

echo "→ إعادة التسمية إلى مخطط legacy…"
# التفريغ يحمل search_path للمخطط public؛ نحوّله ليهبط في legacy بدل الكتابة فوق الهدف
{
  echo 'drop schema if exists legacy cascade;'
  echo 'create schema legacy;'
  echo "set search_path = legacy;"
  grep -v '^SET search_path' "$DUMP_FILE" | sed 's/\bpublic\./legacy./g'
} | psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -X -q

echo "✓ المصدر متاح في مخطط legacy. التالي: 01-source-adapter.sql"
