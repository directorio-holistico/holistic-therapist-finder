<#
.SYNOPSIS
  Recreates the local TEST database from scratch: roles, auth stub and all migrations.
  Recrea desde cero la base de datos local de PRUEBA: roles, stub de auth y todas las migraciones.

.DESCRIPTION
  Safety rules / Reglas de seguridad:
  - Only touches the database named therapist_finder_test.
  - Only connects to localhost.
  - The password is asked once and kept only in this process; it is never written to disk.
  Solo toca la base therapist_finder_test, solo se conecta a localhost y la contrasena se pide una
  vez, queda solo en este proceso y nunca se escribe en disco.

  NOTE / NOTA: this file is plain ASCII on purpose. Windows PowerShell 5 reads files without a BOM
  as ANSI, and accented characters can turn into quote characters and break the script.
  Este archivo es ASCII puro a proposito: Windows PowerShell 5 lee como ANSI los archivos sin BOM y
  las letras con tilde pueden convertirse en comillas y romper el script.
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

# Find psql / Buscar psql
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $candidate = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($candidate) { $psql = $candidate.FullName }
}
if (-not $psql) {
  throw "psql not found. Install PostgreSQL 17 first / No se encontro psql. Instala PostgreSQL 17 primero."
}

# Ask for the password once; keep it only in this process.
# Pedir la contrasena una vez; queda solo en este proceso.
$secure = Read-Host "Password for '$AdminUser' on ${DbHost}:${Port} / Contrasena de '$AdminUser'" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
# Send and read SQL files as UTF-8 (Supabase databases are UTF-8).
# Enviar y leer los archivos SQL como UTF-8 (las bases de Supabase son UTF-8).
$env:PGCLIENTENCODING = "UTF8"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$common = @("-X", "-v", "ON_ERROR_STOP=1", "-h", $DbHost, "-p", "$Port", "-U", $AdminUser)

function Invoke-Psql {
  param([string[]]$PsqlArgs)
  & $psql @common @PsqlArgs
  if ($LASTEXITCODE -ne 0) { throw "psql failed with exit code $LASTEXITCODE" }
}

try {
  Write-Host "Recreating database $DbName / Recreando la base $DbName ..."
  Invoke-Psql @("-d", "postgres", "-c", "DROP DATABASE IF EXISTS $DbName WITH (FORCE)")
  Invoke-Psql @("-d", "postgres", "-c", "CREATE DATABASE $DbName ENCODING 'UTF8' TEMPLATE template0")

  Write-Host "Applying roles and auth stub / Aplicando roles y stub de auth ..."
  Invoke-Psql @("-d", $DbName, "-f", (Join-Path $repoRoot "supabase\local\roles.sql"))

  $migrations = Get-ChildItem (Join-Path $repoRoot "supabase\migrations") -Filter "*.sql" -ErrorAction SilentlyContinue |
    Sort-Object Name
  foreach ($m in $migrations) {
    Write-Host "Applying migration / Aplicando migracion: $($m.Name)"
    Invoke-Psql @("-d", $DbName, "-f", $m.FullName)
  }
  if (-not $migrations) {
    Write-Host "No migrations yet / Todavia no hay migraciones."
  }
  Write-Host "Done / Listo."
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\PGCLIENTENCODING -ErrorAction SilentlyContinue
}
