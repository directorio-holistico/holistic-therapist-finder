# Supabase setup: applying the database to a real project
# Puesta en marcha de Supabase: aplicar la base a un proyecto real

English first, Spanish below. / Primero inglés, abajo español.

---

## English

**Rule:** migrations are tested on the local test database first (CI does it on every push). Only then they are applied to the real project, one by one, each in a single transaction, with its read-only verification. The SQL tests, the roles stub and the dev seed are **never** run on the real project.

### 0. Before you start
- A **dedicated Supabase organization** for this project (Free plan: 2 active projects per organization), so it does not share members, billing or limits with other systems.
- PostgreSQL 17 client tools on your machine (`psql`), the same ones used for the local test database.
- The database password is created with the project. Keep it in a password manager. **Never** put it in the repo, in a chat or in a file.

### 1. Create the project
1. New project, region **South America (São Paulo)**, Free plan.
2. In the creation screen leave **"Automatically expose new tables and functions" unchecked**. The baseline migration closes those defaults anyway; doing both is deliberate.
3. Write down the **project reference** (the 20-character code in the project URL) and, from **Connect > Session pooler**, the **host** (`aws-N-sa-east-1.pooler.supabase.com`). The direct connection is IPv6-only on the Free plan; the session pooler works over IPv4.

### 2. Apply the migrations
```powershell
cd "<repo folder>"
.\scripts\db\Apply-Remote.ps1 -ProjectRef <ref> -PoolerHost <host> -DryRun   # only lists / solo lista
.\scripts\db\Apply-Remote.ps1 -ProjectRef <ref> -PoolerHost <host> -PauseEach
```
It asks you to retype the reference, then the password (hidden). After each migration it runs the read-only verification and shows it. If one fails it changes nothing and stops; fix it and continue with `-From <version>` of the failed one.

### 3. Test anonymous access
```powershell
.\scripts\db\Test-RemoteAnon.ps1 -ProjectRef <ref>
```
It asks for the **public anon key** (Project Settings > API Keys). Every line must say PASS. **Do not publish while any line fails.** The script refuses a `service_role` key.

### 4. First administrator
1. Dashboard > Authentication > Users > add the administrator's user.
2. In the SQL editor run the script in section "First administrator SQL" below with your real data. **Do not save it in the repo.**
3. Changes made in the SQL editor appear in the audit log with a null role: expected.

### 5. Keys and environment variables
- `anon` key (public) and project URL: Vercel and `.env.local`.
- `service_role` key: only in server environment variables (Vercel, `.env.local`). Never in the repo, never in the browser. If it leaks, rotate it in the dashboard.
- `.env.example` keeps empty values.

### 6. Known limits of the Free plan
- A Free project is paused after 7 days of low activity; paid projects are never paused. A pause stops the site. Decision pending (ADR-0002).
- The Free plan has no backups: a scheduled `pg_dump` with a tested restore is required before publishing.
- Limited auth emails: a custom SMTP is needed before inviting therapists.

### First administrator SQL (template: replace the placeholders, do not commit)
```sql
begin;
insert into public.people (auth_user_id, full_name, email)
  select id, 'FULL NAME', lower(email) from auth.users where email = 'ADMIN@EXAMPLE.COM';
insert into public.person_roles (person_id, role_id)
  select p.id, r.id from public.people p cross join public.roles r
   where p.email = lower('ADMIN@EXAMPLE.COM') and r.code = 'admin';
select p.id, r.code from public.people p join public.person_roles pr on pr.person_id = p.id join public.roles r on r.id = pr.role_id;
commit;
```

---

## Español

**Regla:** las migraciones se prueban primero en la base local de prueba (el CI lo hace en cada push). Recién después se aplican al proyecto real, una por una, cada una en una sola transacción, con su verificación de solo lectura. Las pruebas SQL, el stub de roles y los datos de ejemplo **nunca** se corren en el proyecto real.

### 0. Antes de empezar
- Una **organización de Supabase dedicada** a este proyecto (plan gratis: 2 proyectos activos por organización), para no compartir miembros, facturación ni límites con otros sistemas.
- Las herramientas de PostgreSQL 17 en tu máquina (`psql`), las mismas de la base local de prueba.
- La contraseña de la base se crea con el proyecto. Guardala en un gestor de contraseñas. **Nunca** en el repo, en un chat ni en un archivo.

### 1. Crear el proyecto
1. Proyecto nuevo, región **South America (São Paulo)**, plan gratis.
2. En la pantalla de creación dejá **sin marcar** "Automatically expose new tables and functions". La migración base igual cierra esos permisos; hacer las dos cosas es a propósito.
3. Anotá la **referencia del proyecto** (el código de 20 caracteres de la URL) y, en **Connect > Session pooler**, el **host** (`aws-N-sa-east-1.pooler.supabase.com`). La conexión directa es solo IPv6 en el plan gratis; el pooler de sesión funciona por IPv4.

### 2. Aplicar las migraciones
Los comandos son los de la sección en inglés. `-DryRun` solo lista; `-PauseEach` espera un Enter antes de cada migración. El script te pide volver a escribir la referencia y luego la contraseña (oculta). Después de cada migración corre su verificación de solo lectura y te la muestra. Si una falla, no cambia nada y se detiene: se corrige y se continúa con `-From <versión>` de la que falló.

### 3. Probar el acceso anónimo
Comando en la sección en inglés. Pide la **clave pública anon** (Project Settings > API Keys). Todas las líneas deben decir PASS. **No publicar mientras alguna falle.** El script rechaza una clave `service_role`.

### 4. Primer administrador
1. Dashboard > Authentication > Users > agregar el usuario del administrador.
2. En el editor SQL correr el script de "First administrator SQL" con tus datos reales. **No guardarlo en el repo.**
3. Los cambios hechos en el editor SQL aparecen en la auditoría con rol nulo: es lo esperado.

### 5. Claves y variables de entorno
- Clave `anon` (pública) y URL del proyecto: Vercel y `.env.local`.
- Clave `service_role`: solo en variables de entorno del servidor (Vercel, `.env.local`). Nunca en el repo ni en el navegador. Si se filtra, se rota desde el panel.
- `.env.example` queda con valores vacíos.

### 6. Límites conocidos del plan gratis
- Un proyecto gratis se pausa tras 7 días de poca actividad; los pagos nunca se pausan. La pausa frena el sitio. Decisión pendiente (ADR-0002).
- El plan gratis no trae backups: antes de publicar hace falta un `pg_dump` programado con restauración probada.
- Los mails de Auth son limitados: hace falta un SMTP propio antes de invitar terapeutas.
