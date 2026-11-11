#!/usr/bin/env bash
# Rebuilds the throwaway test database and runs every SQL test (used by CI; also works locally on Linux/macOS).
# Reconstruye la base de prueba descartable y corre todas las pruebas SQL (la usa el CI; sirve también en Linux/macOS).
#
# Connection comes from the standard PG* variables (PGHOST, PGPORT, PGUSER, PGPASSWORD).
# La conexión sale de las variables estándar PG* (PGHOST, PGPORT, PGUSER, PGPASSWORD).
# Safety: only touches the database named therapist_finder_test, and only on localhost.
# Seguridad: solo toca la base therapist_finder_test, y solo en localhost.
set -euo pipefail

DB="therapist_finder_test"
HOST="${PGHOST:-localhost}"
case "$HOST" in
  localhost|127.0.0.1|::1|/*) ;;
  *) echo "Refusing to run: host must be local / Se niega a correr: el host debe ser local" >&2; exit 1 ;;
esac

export PGCLIENTENCODING=UTF8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
psql_admin() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

echo "Recreating $DB / Recreando $DB"
psql_admin -d postgres -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)"
psql_admin -d postgres -c "CREATE DATABASE $DB ENCODING 'UTF8' TEMPLATE template0"

echo "Roles and auth stub / Roles y stub de auth"
psql_admin -d "$DB" -f "$ROOT/supabase/local/roles.sql" >/dev/null

for m in "$ROOT"/supabase/migrations/*.sql; do
  [ -e "$m" ] || continue
  echo "Migration / Migración: $(basename "$m")"
  psql_admin -d "$DB" -1 -f "$m" >/dev/null
done

if [ -f "$ROOT/supabase/seed/dev-seed.sql" ]; then
  echo "Dev seed / Datos de ejemplo"
  psql_admin -d "$DB" -f "$ROOT/supabase/seed/dev-seed.sql" >/dev/null
fi

failed=0
for t in "$ROOT"/supabase/tests/*.test.sql; do
  echo "== $(basename "$t")"
  if ! psql_admin -d "$DB" -f "$t"; then
    echo "FAILED / FALLO: $(basename "$t")" >&2
    failed=$((failed + 1))
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "$failed test file(s) failed / $failed archivo(s) de prueba fallaron" >&2
  exit 1
fi
echo "All SQL tests passed / Todas las pruebas SQL pasaron"
