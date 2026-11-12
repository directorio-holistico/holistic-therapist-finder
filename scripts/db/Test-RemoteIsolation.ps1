<#
.SYNOPSIS
  Isolation test against a REAL Supabase project: 2 fictitious therapists + the administrator, through the public REST API.
  Prueba de aislamiento contra un proyecto REAL de Supabase: 2 terapeutas ficticios + el administrador, por la API REST publica.

.DESCRIPTION
  Needs 3 users that already exist in Authentication (confirmed): the administrator (already set up as admin) and two
  fictitious therapists. It signs them in with email and password (typed without echo, kept only in this process), registers
  the two fictitious therapists with register_therapist (the real registration function) and checks:
  - each therapist sees only their own person and profile, never the other's;
  - a therapist cannot write, cannot see the audit log, cannot see private settings, cannot call internal functions;
  - the administrator sees everyone and the audit log.
  It CREATES two test therapists (person + empty unpublished profile). Remove them afterwards: see docs/supabase-setup.md.
  Necesita 3 usuarios que ya existan en Authentication (confirmados): el administrador (ya dado de alta como admin) y dos
  terapeutas ficticios. Los ingresa con mail y contrasena (sin eco, solo en este proceso), registra a los dos ficticios con
  register_therapist (la funcion real de alta) y comprueba:
  - cada terapeuta ve solo su persona y su perfil, nunca los del otro;
  - un terapeuta no puede escribir, ni ver el registro de auditoria, ni los ajustes privados, ni llamar funciones internas;
  - el administrador ve a todos y el registro de auditoria.
  CREA dos terapeutas de prueba (persona + perfil vacio sin publicar). Borralos despues: ver docs/supabase-setup.md.

  Use the PUBLIC anon key, never service_role. / Usa la clave PUBLICA anon, nunca la service_role.
  NOTE / NOTA: plain ASCII on purpose (see Reset-LocalDb.ps1). / ASCII puro a proposito.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectRef
)

$ErrorActionPreference = "Stop"
if ($ProjectRef -notmatch '^[a-z0-9]{10,30}$') { throw "ProjectRef looks wrong / La referencia del proyecto no parece correcta." }
$rest = "https://$ProjectRef.supabase.co/rest/v1"
$auth = "https://$ProjectRef.supabase.co/auth/v1"

function Read-Secret {
  param([string]$Prompt)
  $s = Read-Host $Prompt -AsSecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

$anon = Read-Secret "PUBLIC anon key (not service_role) / Clave PUBLICA anon (no service_role)"
if ($anon.Length -lt 20) { throw "The key looks too short / La clave parece muy corta." }
$parts = $anon.Split(".")
if ($parts.Count -eq 3) {
  $p = $parts[1].Replace("-", "+").Replace("_", "/")
  while ($p.Length % 4 -ne 0) { $p += "=" }
  try {
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
    if ($json -match '"role"\s*:\s*"service_role"') { throw "That is a service_role key: STOP and rotate it / Esa es una clave service_role: PARA y rotala." }
  } catch [System.FormatException] { }
}

function Get-Token {
  param([string]$Email, [string]$Password)
  $body = @{ email = $Email; password = $Password } | ConvertTo-Json
  try {
    $r = Invoke-WebRequest -Method Post -Uri "$auth/token?grant_type=password" -UseBasicParsing `
      -Headers @{ "apikey" = $anon; "Content-Type" = "application/json" } -Body $body
  } catch {
    throw "Sign-in failed for $Email (wrong password, unconfirmed user or no such user) / Fallo el ingreso de $Email (contrasena incorrecta, usuario sin confirmar o inexistente)."
  }
  return ($r.Content | ConvertFrom-Json).access_token
}

function Invoke-Api {
  param([string]$Token, [string]$Method, [string]$Path, [string]$Body = $null)
  $h = @{ "apikey" = $anon; "Authorization" = "Bearer $Token"; "Content-Type" = "application/json" }
  try {
    if ($Body) { $r = Invoke-WebRequest -Method $Method -Uri "$rest/$Path" -Headers $h -Body $Body -UseBasicParsing }
    else { $r = Invoke-WebRequest -Method $Method -Uri "$rest/$Path" -Headers $h -UseBasicParsing }
    return [pscustomobject]@{ Status = [int]$r.StatusCode; Content = [string]$r.Content }
  } catch {
    if ($_.Exception.Response) { return [pscustomobject]@{ Status = [int]$_.Exception.Response.StatusCode; Content = "" } }
    throw
  }
}

function Get-Rows {
  param($Response)
  if ($Response.Status -lt 200 -or $Response.Status -ge 300) { return -1 }
  $c = $Response.Content.Trim()
  if ($c -eq "" -or $c -eq "[]") { return 0 }
  return @($c | ConvertFrom-Json).Count
}

$failures = 0
function Check {
  param([string]$Label, [bool]$Ok, [string]$Detail = "")
  if ($Ok) { Write-Host ("PASS  {0,-62} {1}" -f $Label, $Detail) -ForegroundColor Green }
  else { Write-Host ("FAIL  {0,-62} {1}" -f $Label, $Detail) -ForegroundColor Red; $script:failures++ }
}

Write-Host "Three users that already exist and are confirmed / Tres usuarios que ya existen y estan confirmados" -ForegroundColor Cyan
$adminEmail = (Read-Host "Administrator email / Mail del administrador").Trim().ToLower()
$adminPass = Read-Secret "Administrator password / Contrasena del administrador"
$aEmail = (Read-Host "Fictitious therapist A email / Mail del terapeuta ficticio A").Trim().ToLower()
$aPass = Read-Secret "Therapist A password / Contrasena del terapeuta A"
$bEmail = (Read-Host "Fictitious therapist B email / Mail del terapeuta ficticio B").Trim().ToLower()
$bPass = Read-Secret "Therapist B password / Contrasena del terapeuta B"
if (@($adminEmail, $aEmail, $bEmail | Select-Object -Unique).Count -ne 3) { throw "The three emails must be different / Los tres mails deben ser distintos." }

$tAdmin = Get-Token $adminEmail $adminPass
$tA = Get-Token $aEmail $aPass
$tB = Get-Token $bEmail $bPass
Check "sign-in of the three users / ingreso de los tres usuarios" $true

# 1) Registration with the real function (200 = created, 409 = already registered in a previous run)
$accept = '{"terms":"2026-11","privacy":"2026-11","legal_declaration":"2026-11"}'
$rA = Invoke-Api $tA "POST" "rpc/register_therapist" ('{"p_full_name":"Terapeuta Prueba A","p_acceptances":' + $accept + '}')
Check "A: register_therapist" ($rA.Status -eq 200 -or $rA.Status -eq 409) "status $($rA.Status)"
$rB = Invoke-Api $tB "POST" "rpc/register_therapist" ('{"p_full_name":"Terapeuta Prueba B","p_acceptances":' + $accept + '}')
Check "B: register_therapist" ($rB.Status -eq 200 -or $rB.Status -eq 409) "status $($rB.Status)"

# 2) Each therapist sees only their own person and profile
$pa = Invoke-Api $tA "GET" "people?select=id,email"
$pb = Invoke-Api $tB "GET" "people?select=id,email"
Check "A sees exactly 1 person (own) / A ve 1 sola persona (la suya)" ((Get-Rows $pa) -eq 1 -and $pa.Content -match [regex]::Escape($aEmail)) "rows $(Get-Rows $pa)"
Check "B sees exactly 1 person (own) / B ve 1 sola persona (la suya)" ((Get-Rows $pb) -eq 1 -and $pb.Content -match [regex]::Escape($bEmail)) "rows $(Get-Rows $pb)"
$xa = Invoke-Api $tA "GET" ("people?select=id&email=eq." + [uri]::EscapeDataString($bEmail))
Check "A cannot see B's person / A no ve la persona de B" ((Get-Rows $xa) -eq 0) "rows $(Get-Rows $xa)"

$fa = Invoke-Api $tA "GET" "therapist_profiles?select=id"
$fb = Invoke-Api $tB "GET" "therapist_profiles?select=id"
Check "A sees exactly 1 profile (own) / A ve 1 solo perfil (el suyo)" ((Get-Rows $fa) -eq 1) "rows $(Get-Rows $fa)"
Check "B sees exactly 1 profile (own) / B ve 1 solo perfil (el suyo)" ((Get-Rows $fb) -eq 1) "rows $(Get-Rows $fb)"
if ((Get-Rows $fa) -eq 1 -and (Get-Rows $fb) -eq 1) {
  $idA = (@($fa.Content | ConvertFrom-Json))[0].id
  $idB = (@($fb.Content | ConvertFrom-Json))[0].id
  Check "profile ids differ / los perfiles son distintos" ($idA -ne $idB)
  $cross = Invoke-Api $tA "GET" ("therapist_profiles?select=id&id=eq." + $idB)
  Check "A cannot read B's profile by id / A no lee el perfil de B por id" ((Get-Rows $cross) -eq 0) "rows $(Get-Rows $cross)"
  $w1 = Invoke-Api $tA "PATCH" ("therapist_profiles?id=eq." + $idA) '{"headline":"hack"}'
  Check "A cannot edit own profile directly / A no edita su perfil directo" ($w1.Status -lt 200 -or $w1.Status -ge 300) "status $($w1.Status)"
  $w2 = Invoke-Api $tA "PATCH" ("therapist_profiles?id=eq." + $idB) '{"headline":"hack"}'
  Check "A cannot edit B's profile / A no edita el perfil de B" ($w2.Status -lt 200 -or $w2.Status -ge 300) "status $($w2.Status)"
}

# 3) A therapist cannot write, nor read what is for the administrator, nor call internal functions
$w3 = Invoke-Api $tA "POST" "people" '{"full_name":"hack","email":"hack@example.test"}'
Check "A cannot insert into people / A no inserta en people" ($w3.Status -lt 200 -or $w3.Status -ge 300) "status $($w3.Status)"
$au = Invoke-Api $tA "GET" "audit_log?select=id"
Check "A cannot read the audit log / A no lee la auditoria" ((Get-Rows $au) -le 0) "rows $(Get-Rows $au)"
$ps = Invoke-Api $tA "GET" "app_settings?select=key&is_public=eq.false"
Check "A cannot read private settings / A no lee ajustes privados" ((Get-Rows $ps) -le 0) "rows $(Get-Rows $ps)"
$z = "00000000-0000-0000-0000-000000000000"
$f1 = Invoke-Api $tA "POST" "rpc/reveal_contact" ('{"p_profile_id":"' + $z + '"}')
Check "A cannot call reveal_contact / A no llama reveal_contact" ($f1.Status -lt 200 -or $f1.Status -ge 300) "status $($f1.Status)"
$f2 = Invoke-Api $tA "POST" "rpc/reveal_contact_limited" ('{"p_profile_id":"' + $z + '","p_origin_hash":"' + ("0" * 64) + '"}')
Check "A cannot call reveal_contact_limited / A no llama reveal_contact_limited" ($f2.Status -lt 200 -or $f2.Status -ge 300) "status $($f2.Status)"
$f3 = Invoke-Api $tA "POST" "rpc/purge_expired_audit_log" "{}"
Check "A cannot call purge_expired_audit_log / A no llama la purga" ($f3.Status -lt 200 -or $f3.Status -ge 300) "status $($f3.Status)"
$ia = Invoke-Api $tA "POST" "rpc/is_admin" "{}"
Check "A is not administrator / A no es administrador" ($ia.Status -eq 200 -and $ia.Content.Trim() -eq "false") "answer $($ia.Content.Trim())"

# 4) The administrator sees everyone and the audit log
$ad = Invoke-Api $tAdmin "POST" "rpc/is_admin" "{}"
Check "administrator is_admin = true / el administrador es admin" ($ad.Status -eq 200 -and $ad.Content.Trim() -eq "true") "answer $($ad.Content.Trim())"
$ap = Invoke-Api $tAdmin "GET" "people?select=id"
Check "administrator sees at least 3 people / el admin ve al menos 3 personas" ((Get-Rows $ap) -ge 3) "rows $(Get-Rows $ap)"
$al = Invoke-Api $tAdmin "GET" "audit_log?select=id&limit=1"
Check "administrator reads the audit log / el admin lee la auditoria" ((Get-Rows $al) -ge 1) "rows $(Get-Rows $al)"

if ($failures -gt 0) { throw "$failures check(s) failed: do NOT publish / $failures comprobacion(es) fallaron: NO publicar." }
Write-Host "Isolation is as designed / El aislamiento es el disenado." -ForegroundColor Green
Write-Host "Now remove the two test therapists (docs/supabase-setup.md) / Ahora borra a los dos terapeutas de prueba (docs/supabase-setup.md)."
