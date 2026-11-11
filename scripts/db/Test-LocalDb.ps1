<#
.SYNOPSIS
  Runs every SQL test in supabase/tests against the local TEST database.
  Ejecuta todas las pruebas SQL de supabase/tests contra la base local de PRUEBA.

.DESCRIPTION
  A test fails if psql exits with an error (the tests raise exceptions). Run Reset-LocalDb.ps1 first.
  Una prueba falla si psql termina con error (las pruebas lanzan excepciones). Corre antes Reset-LocalDb.ps1.

  NOTE / NOTA: this file is plain ASCII on purpose (see Reset-LocalDb.ps1).
  Este archivo es ASCII puro a proposito (ver Reset-LocalDb.ps1).
#>
[CmdletBinding()]
param(
  [string]$DbHost = "localhost",
  [int]$Port = 5432,
  [string]$AdminUser = "postgres"
)

$ErrorActionPreference = "Stop"
$DbName = "therapist_finder_test"

if ($DbHost -notin @("localhost", "127.0.0.1", "::1")) {
  throw "Refusing to run: host must be localhost / Se niega a correr: el host debe ser localhost."
}

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $candidate = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($candidate) { $psql = $candidate.FullName }
}
if (-not $psql) {
  throw "psql not found. Install PostgreSQL 17 first / No se encontro psql. Instala PostgreSQL 17 primero."
}

$secure = Read-Host "Password for '$AdminUser' on ${DbHost}:${Port} / Contrasena de '$AdminUser'" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
$env:PGCLIENTENCODING = "UTF8"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$tests = Get-ChildItem (Join-Path $repoRoot "supabase\tests") -Filter "*.test.sql" | Sort-Object Name
$failed = 0

try {
  foreach ($t in $tests) {
    Write-Host "== $($t.Name)"
    & $psql -X -v ON_ERROR_STOP=1 -h $DbHost -p $Port -U $AdminUser -d $DbName -f $t.FullName
    if ($LASTEXITCODE -ne 0) {
      Write-Host "FAILED / FALLO: $($t.Name)" -ForegroundColor Red
      $failed++
    }
  }
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\PGCLIENTENCODING -ErrorAction SilentlyContinue
}

if ($failed -gt 0) { throw "$failed test file(s) failed / $failed archivo(s) de prueba fallaron." }
Write-Host "All SQL tests passed / Todas las pruebas SQL pasaron." -ForegroundColor Green
