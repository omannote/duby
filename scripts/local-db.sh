#!/usr/bin/env bash
# يعيد بناء قاعدة اختبار محلية من الصفر: bootstrap ثم كل الهجرات بالترتيب.
# بديل عن Supabase CLI حين لا يتوفر Docker.
set -euo pipefail

PORT="${PGPORT:-54399}"
HOST="${PGHOST:-/tmp}"
DB="${PGDATABASE:-duby_test}"
PSQL=(psql -h "$HOST" -p "$PORT" -U postgres -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -d postgres -c "drop database if exists $DB;" -c "create database $DB;"

"${PSQL[@]}" -d "$DB" -f tests/db/bootstrap-local.sql

for migration in supabase/migrations/*.sql; do
  echo "→ $(basename "$migration")"
  "${PSQL[@]}" -d "$DB" -f "$migration"
done

echo "✓ قاعدة الاختبار جاهزة: $DB"
