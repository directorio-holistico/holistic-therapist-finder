<#
.SYNOPSIS
  Loads, checks or removes the 6 FICTITIOUS DEMO therapists in a REAL Supabase project.
  Carga, revisa o quita los 6 terapeutas FICTICIOS DEMO en un proyecto REAL de Supabase.

.DESCRIPTION
  -Action Check  : read-only, counts DEMO records and lists them. / Solo lectura: cuenta y lista los registros DEMO.
  -Action Load   : runs supabase\demo\seed-demo.sql in ONE transaction (all or nothing). Refuses if DEMO data already exists.
                   Corre supabase\demo\seed-demo.sql en UNA transaccion. Se niega si ya hay datos DEMO.
  -Action Remove : runs supabase\demo\remove-demo.sql (deletes only people marked @demo.invalid AND "[DEMO] "). You must type
                   BORRAR DEMO to confirm. Run it BEFORE opening the site to the public.
                   Borra solo personas marcadas @demo.invalid Y "[DEMO] ". Hay que escribir BORRAR DEMO. Correrlo ANTES de abrir al publico.

  Same safety rules as Apply-Remote.ps1: only the Supabase shared pooler on port 5432, you retype the project reference,
  the password is asked hidden and kept only in this process. / Mismas reglas que Apply-Remote.ps1.

  NOTE / NOTA: plain ASCII on purpose. / ASCII puro a proposito.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet("Check", "Load", "Remove")][string]$Action,
  [Parameter(Mandatory = $true)][string]$ProjectRef,
  [Parameter(Mandatory = $true)][string]$PoolerHost,
  [int]$Port = 5432
)

$ErrorActionPreference = "Stop"

if ($ProjectRef -notmatch '^[a-z0-9]{10,30}$') {
  throw "ProjectRef looks wrong / La referencia del proyecto no parece correcta."
}
if ($PoolerHost -notmatch '^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$') {
  throw "Refusing: the host must be the Supabase shared pooler / Se niega: el host debe ser el pooler compartido de Supabase."
}
if ($Port -ne 5432) { throw "Refusing: use port 5432 / Se niega: usa el puerto 5432." }
$DbUser = "postgres.$ProjectRef"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$fileName = switch ($Action) { "Check" { "check-demo.sql" } "Load" { "seed-demo.sql" } "Remove" { "remove-demo.sql" } }
$sqlFile = Join-Path $repoRoot ("supabase\demo\" + $fileName)
if (-not (Test-Path -LiteralPath $sqlFile)) { throw "File not found / No se encuentra: $sqlFile" }

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $candidate = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($candidate) { $psql = $candidate.FullName }
}
if (-not $psql) { throw "psql not found / No se encontro psql." }

$typed = Read-Host "Type the project reference to confirm the target / Escribi la referencia del proyecto para confirmar"
if ($typed -ne $ProjectRef) { throw "Reference does not match: nothing was done / La referencia no coincide: no se hizo nada." }

if ($Action -eq "Remove") {
  $word = Read-Host "This DELETES the DEMO profiles. Type BORRAR DEMO to continue / Esto BORRA los perfiles DEMO. Escribi BORRAR DEMO para seguir"
  if ($word -cne "BORRAR DEMO") { throw "Not confirmed: nothing was done / Sin confirmar: no se hizo nada." }
}

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
  Write-Host "Running / Ejecutando: $fileName ($Action)" -ForegroundColor Cyan
  if ($Action -eq "Check") {
    & $psql @common -f $sqlFile
  } else {
    & $psql @common -1 -f $sqlFile
  }
  if ($LASTEXITCODE -ne 0) { throw "Failed and changed nothing / Fallo y no cambio nada." }
  if ($Action -ne "Check") {
    Write-Host "Check after the change (read-only) / Chequeo posterior (solo lectura):" -ForegroundColor Cyan
    & $psql @common -f (Join-Path $repoRoot "supabase\demo\check-demo.sql")
    if ($LASTEXITCODE -ne 0) { throw "Check failed / Fallo el chequeo." }
  }
  Write-Host "Done / Listo." -ForegroundColor Green
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\PGCLIENTENCODING -ErrorAction SilentlyContinue
  Remove-Item Env:\PGSSLMODE -ErrorAction SilentlyContinue
}
