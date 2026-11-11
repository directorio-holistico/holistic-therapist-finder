# Local test database / Base de datos local de prueba

## English
Migrations are tested first on a plain local PostgreSQL that emulates the Supabase roles (`anon`, `authenticated`, `service_role`, `authenticator`) and the `auth.uid()` helper. Supabase itself is built on PostgreSQL; this emulates only the database part (no Auth service, no API, no Storage).

Requirements: PostgreSQL 17 installed on Windows (Supabase's default major version at the time of writing), and `psql` available.

```powershell
# 1. Recreate the test database (asks for the postgres password once; it is never stored)
.\scripts\db\Reset-LocalDb.ps1

# 2. Run the SQL tests
.\scripts\db\Test-LocalDb.ps1
```

Safety: the scripts only connect to `localhost` and only touch the database `therapist_finder_test`. `supabase/local/roles.sql` must never be run against a real Supabase project.

Tests impersonate roles with `SET SESSION AUTHORIZATION authenticator` + `SET ROLE <role>`, so `session_user` and `current_user` match what the API sees.

## Español
Las migraciones se prueban primero en un PostgreSQL local común que emula los roles de Supabase (`anon`, `authenticated`, `service_role`, `authenticator`) y la función `auth.uid()`. Supabase está construido sobre PostgreSQL; esto emula solo la parte de base de datos (sin el servicio de Auth, sin la API y sin Storage).

Requisitos: PostgreSQL 17 instalado en Windows (versión por defecto de Supabase al escribir esto) y `psql` disponible.

```powershell
# 1. Recrear la base de prueba (pide la contraseña de postgres una vez; no se guarda)
.\scripts\db\Reset-LocalDb.ps1

# 2. Ejecutar las pruebas SQL
.\scripts\db\Test-LocalDb.ps1
```

Seguridad: los scripts solo se conectan a `localhost` y solo tocan la base `therapist_finder_test`. `supabase/local/roles.sql` no se ejecuta nunca en un proyecto real de Supabase.

Las pruebas suplantan roles con `SET SESSION AUTHORIZATION authenticator` + `SET ROLE <rol>`, así `session_user` y `current_user` coinciden con lo que ve la API.
