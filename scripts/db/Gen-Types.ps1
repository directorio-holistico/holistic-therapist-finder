<#
Gen-Types.ps1
EN: Generates TypeScript types from the REAL Supabase database (public schema)
    and writes them as UTF-8 without BOM to src/lib/supabase/database.types.ts.
    The access token is typed hidden, lives only in this process, never on disk.
ES: Genera los tipos TypeScript desde la base REAL (esquema public) y los
    escribe en UTF-8 sin BOM. El token se escribe oculto y no se guarda.

Uso / Usage:  .\scripts\db\Gen-Types.ps1
Token: https://supabase.com/dashboard/account/tokens (crear uno, borrarlo despues)
#>
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dest = Join-Path $repo 'src\lib\supabase\database.types.ts'

$ref = Read-Host 'Project ref (ej: el codigo de 20 letras del proyecto)'
if ($ref -notmatch '^[a-z]{20}$') { throw 'El project ref debe tener 20 letras minusculas.' }

$secure = Read-Host 'Access token de Supabase (oculto)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$errFile = Join-Path $env:TEMP 'gen-types-stderr.txt'

try {
  $env:SUPABASE_ACCESS_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Host 'Generando tipos (puede tardar unos segundos)...'
  # PS 5.1 turns native stderr (warnings) into errors under 'Stop'; relax only here.
  $ErrorActionPreference = 'Continue'
  $lines = & npx.cmd --yes supabase gen types typescript "--remote=$ref" --schema public 2> $errFile
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -ne 0) {
    Write-Host (Get-Content -LiteralPath $errFile -Encoding UTF8 -Raw)
    throw "El generador fallo (codigo $code)."
  }
}
finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  Remove-Item Env:\SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
}

$text = ($lines -join "`n") + "`n"
foreach ($must in @('export type Database', 'public_profile_cards', 'search_profiles', 'rates_current')) {
  if ($text -notmatch [regex]::Escape($must)) { throw "Salida inesperada: falta '$must'. No escribo el archivo." }
}

New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
[System.IO.File]::WriteAllText($dest, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK: $dest ($($text.Length) caracteres)"
Write-Host 'Siguiente: npx tsc --noEmit'
