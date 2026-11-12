<#
.SYNOPSIS
  Applies the migrations in supabase\migrations to a REAL Supabase project, one by one, each in a single transaction.
  Aplica las migraciones de supabase\migrations a un proyecto REAL de Supabase, una por una, cada una en una sola transaccion.

.DESCRIPTION
  Safety rules / Reglas de seguridad:
  - Connects only through the Supabase shared pooler in session mode (host aws-N-region.pooler.supabase.com, port 5432,
    IPv4). Any other host is refused. / Solo se conecta por el pooler compartido de Supabase en modo sesion; cualquier otro
    host se rechaza.
  - You must type the project reference again to confirm the target. / Hay que volver a escribir la referencia del proyecto.
  - The password is asked once, kept only in this process and never written to disk or to the repo. / La contrasena se pide
    una vez, queda solo en este proceso y nunca se escribe en disco ni en el repo.
  - Each migration runs with psql -1 (BEGIN ... COMMIT): if it fails, that migration changes nothing. The read-only
    verification file of each migration (supabase\verification\<name>.verify.sql) runs right after it and its output is shown.
    Cada migracion corre con psql -1 (BEGIN ... COMMIT): si falla, esa migracion no cambia nada. El archivo de verificacion
    de solo lectura de cada migracion corre justo despues y se muestra su salida.
  - Without -From the project must have NO tables in schema public (a clean project). / Sin -From el proyecto debe estar
    limpio (sin tablas en el esquema public).
  - NEVER runs the SQL tests, the roles stub or the dev seed: those are for the local test database only. / NUNCA corre las
    pruebas SQL, el stub de roles ni los datos de ejemplo: son solo para la base local de prueba.

  Use -DryRun first: it only lists what would be applied. / Usa -DryRun primero: solo lista lo que se aplicaria.

  NOTE / NOTA: plain ASCII on purpose (see Reset-LocalDb.ps1). / ASCII puro a proposito (ver Reset-LocalDb.ps1).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectRef,
  [Parameter(Mandatory = $true)][string]$PoolerHost,
  [int]$Port = 5432,
  [string]$From = "",
  [switch]$DryRun,
  [switch]$PauseEach
)

$ErrorActionPreference = "Stop"

if ($ProjectRef -notmatch '^[a-z0-9]{10,30}$') {
  throw "ProjectRef looks wrong / La referencia del proyecto no parece correcta."
}
if ($PoolerHost -notmatch '^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$') {
  throw "Refusing: the host must be the Supabase shared pooler (aws-N-region.pooler.supabase.com) / Se niega: el host debe ser el pooler compartido de Supabase."
}
if ($Port -ne 5432) {
  throw "Refusing: use the session mode port 5432 / Se niega: usa el puerto 5432 (modo sesion)."
}
$DbUser = "postgres.$ProjectRef"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$migrations = Get-ChildItem (Join-Path $repoRoot "supabase\migrations") -Filter "*.sql" | Sort-Object Name
if ($From -ne "") {
  $migrations = $migrations | Where-Object { $_.BaseName.Split("_")[0] -ge $From }
}
if (-not $migrations) { throw "No migrations to apply / No hay migraciones para aplicar." }

Write-Host "Migrations to apply / Migraciones a aplicar:"
foreach ($m in $migrations) { Write-Host "  $($m.Name)" }
if ($DryRun) { Write-Host "Dry run: nothing was applied / Simulacro: no se aplico nada."; return }

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $candidate = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($candidate) { $psql = $candidate.FullName }
}
if (-not $psql) {
  throw "psql not found. Install PostgreSQL 17 first / No se encontro psql. Instala PostgreSQL 17 primero."
}

$typed = Read-Host "Type the project reference to confirm the target / Escribi la referencia del proyecto para confirmar"
if ($typed -ne $ProjectRef) { throw "Reference does not match: nothing was done / La referencia no coincide: no se hizo nada." }

$secure = Read-Host "Database password of the project / Contrasena de la base del proyecto" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
$env:PGCLIENTENCODING = "UTF8"
$env:PGSSLMODE = "require"

$common = @("-X", "-v", "ON_ERROR_STOP=1", "-h", $PoolerHost, "-p", "$Port", "-U", $DbUser, "-d", "postgres")

try {
  Write-Host "Preflight (read-only) / Chequeo previo (solo lectura) ..."
  $who = & $psql @common -At -c "select current_user"
  if ($LASTEXITCODE -ne 0) { throw "Could not connect / No se pudo conectar." }
  Write-Host "  connected as / conectado como: $who"
  $tables = & $psql @common -At -c "select count(*) from pg_tables where schemaname = 'public'"
  if ($LASTEXITCODE -ne 0) { throw "Preflight query failed / Fallo la consulta previa." }
  if ($From -eq "" -and [int]$tables -gt 0) {
    throw "The project already has $tables table(s) in public. Use -From to continue a partial run / El proyecto ya tiene tablas en public. Usa -From para continuar una corrida parcial."
  }

  foreach ($m in $migrations) {
    if ($PauseEach) { Read-Host "Press Enter to apply $($m.Name) / Enter para aplicar $($m.Name)" | Out-Null }
    Write-Host "Applying / Aplicando: $($m.Name)" -ForegroundColor Cyan
    & $psql @common -1 -f $m.FullName
    if ($LASTEXITCODE -ne 0) { throw "Migration failed and changed nothing: $($m.Name) / La migracion fallo y no cambio nada." }
    $verify = Join-Path $repoRoot ("supabase\verification\" + $m.BaseName + ".verify.sql")
    if (Test-Path -LiteralPath $verify) {
      Write-Host "Verification (read-only) / Verificacion (solo lectura): $($m.BaseName).verify.sql"
      & $psql @common -f $verify
      if ($LASTEXITCODE -ne 0) { throw "Verification query failed: $($m.BaseName) / Fallo la verificacion." }
    }
  }
  Write-Host "All migrations applied / Todas las migraciones aplicadas." -ForegroundColor Green
  Write-Host "Next / Siguiente: run Test-RemoteAnon.ps1 (anonymous access test) / correr Test-RemoteAnon.ps1 (prueba de acceso anonimo)."
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\PGCLIENTENCODING -ErrorAction SilentlyContinue
  Remove-Item Env:\PGSSLMODE -ErrorAction SilentlyContinue
}
