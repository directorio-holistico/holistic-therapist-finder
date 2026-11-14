<#
.SYNOPSIS
  Anonymous access test against a REAL Supabase project, through its public REST API, using only the public (anon) key.
  Prueba de acceso anonimo contra un proyecto REAL de Supabase, por su API REST publica, usando solo la clave publica (anon).

.DESCRIPTION
  Expected / Esperado:
  - the 10 public catalogs and the 2 public views answer 200 (empty list on a clean project);
  - every other table, every internal function and every write is refused (any status outside 2xx).
  - los 10 catalogos publicos y las 2 vistas publicas responden 200 (lista vacia en un proyecto limpio);
  - toda otra tabla, toda funcion interna y toda escritura se rechaza (cualquier estado fuera de 2xx).
  Read-only on a clean project: the only writes it tries must be refused. The key is asked without echo and kept only in this
  process. Use the PUBLIC anon key, never the service_role key. / Solo lectura en un proyecto limpio: las unicas escrituras que
  intenta deben ser rechazadas. La clave se pide sin eco y queda solo en este proceso. Usa la clave PUBLICA (anon), nunca la
  service_role.

  NOTE / NOTA: plain ASCII on purpose (see Reset-LocalDb.ps1). / ASCII puro a proposito.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectRef
)

$ErrorActionPreference = "Stop"
if ($ProjectRef -notmatch '^[a-z0-9]{10,30}$') { throw "ProjectRef looks wrong / La referencia del proyecto no parece correcta." }
$base = "https://$ProjectRef.supabase.co/rest/v1"

$secure = Read-Host "PUBLIC anon key (not service_role) / Clave PUBLICA anon (no service_role)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if ($key.Length -lt 20) { throw "The key looks too short / La clave parece muy corta." }

# Refuse a service_role key: its JWT payload carries the role. / Rechazar una clave service_role: el payload del JWT lleva el rol.
$parts = $key.Split(".")
if ($parts.Count -eq 3) {
  $p = $parts[1].Replace("-", "+").Replace("_", "/")
  while ($p.Length % 4 -ne 0) { $p += "=" }
  try {
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
    if ($json -match '"role"\s*:\s*"service_role"') { throw "That is a service_role key: STOP and rotate it / Esa es una clave service_role: PARA y rotala." }
  } catch [System.FormatException] { }
}

$headers = @{ "apikey" = $key; "Authorization" = "Bearer $key"; "Content-Type" = "application/json" }

function Get-Status {
  param([string]$Method, [string]$Url, [string]$Body = $null)
  try {
    if ($Body) { $r = Invoke-WebRequest -Method $Method -Uri $Url -Headers $headers -Body $Body -UseBasicParsing }
    else { $r = Invoke-WebRequest -Method $Method -Uri $Url -Headers $headers -UseBasicParsing }
    return [int]$r.StatusCode
  } catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
    throw
  }
}

$failures = 0
function Check {
  param([string]$Label, [int]$Status, [bool]$ExpectOk)
  $ok = ($Status -ge 200 -and $Status -lt 300)
  if ($ok -eq $ExpectOk) { Write-Host ("PASS  {0,-55} {1}" -f $Label, $Status) -ForegroundColor Green }
  else { Write-Host ("FAIL  {0,-55} {1} (expected {2})" -f $Label, $Status, $(if ($ExpectOk) { "2xx" } else { "refused" })) -ForegroundColor Red; $script:failures++ }
}

# 1) Public catalogs and views: must answer / Catalogos y vistas publicas: deben responder
$allowed = @("currencies", "languages", "location_levels", "location_translations", "locations", "rate_audiences",
             "service_modes", "session_formats", "therapies", "therapy_translations", "public_profile_cards", "public_profile_detail")
foreach ($t in $allowed) { Check "read $t" (Get-Status "GET" "$base/${t}?select=*&limit=1") $true }

# 1b) New columns of commit 33: visible to visitors through the views and as column grants; person_id stays hidden.
#     Columnas nuevas del commit 33: visibles para los visitantes por las vistas y por permiso de columna; person_id sigue oculto.
Check "read rates columns of public_profile_cards" (Get-Status "GET" "$base/public_profile_cards?select=rates_confirmed_at,rates_current,is_pinned&limit=1") $true
Check "read is_pinned, rates_confirmed_at of therapist_profiles" (Get-Status "GET" "$base/therapist_profiles?select=is_pinned,rates_confirmed_at&limit=1") $true
Check "read person_id of therapist_profiles" (Get-Status "GET" "$base/therapist_profiles?select=person_id&limit=1") $false

# 2) Tables where anon has only SOME columns: reading all columns (select=*) must be refused.
#    Tablas donde anon tiene solo ALGUNAS columnas: leer todas (select=*) se rechaza.
$columnOnly = @("therapist_profiles", "profile_contacts")
foreach ($t in $columnOnly) { Check "read ALL columns of $t" (Get-Status "GET" "$base/${t}?select=*&limit=1") $false }

# 2b) Tables where anon has ALL columns by design (every column is public); rows are limited to published profiles by RLS.
#     select=* answers 2xx here: that is correct. Tablas donde anon tiene TODAS las columnas por diseno (todas son publicas);
#     las filas se limitan a perfiles publicados por RLS. select=* responde 2xx: es lo correcto.
$allColumnsPublic = @("profile_languages", "profile_service_modes", "profile_session_formats", "profile_therapies", "profile_therapy_rates")
foreach ($t in $allColumnsPublic) { Check "read $t (all columns public, rows by RLS)" (Get-Status "GET" "$base/${t}?select=*&limit=1") $true }

# 3) Every other table: refused / Toda otra tabla: rechazada
$others = @("app_settings", "audit_log", "contact_reveals", "contact_types", "erasure_fingerprints", "legal_document_types",
            "moderation_events", "people", "person_roles", "profile_revisions", "profile_statuses", "rate_limit_hits",
            "report_reasons", "report_statuses", "reports", "restricted_terms", "revision_statuses", "roles",
            "terms_acceptances", "unmet_searches")
foreach ($t in $others) { Check "read $t" (Get-Status "GET" "$base/${t}?select=*&limit=1") $false }

# 4) Writes: refused / Escrituras: rechazadas
foreach ($t in @("currencies", "people", "audit_log", "reports", "rate_limit_hits", "unmet_searches")) {
  Check "insert into $t" (Get-Status "POST" "$base/$t" "{}") $false
}
Check "delete from therapies" (Get-Status "DELETE" "$base/therapies?id=gt.0") $false
Check "update therapies" (Get-Status "PATCH" "$base/therapies?id=gt.0" '{"is_active":false}') $false

# 5) Internal functions: refused / Funciones internas: rechazadas
$zero = @("current_person_id", "is_admin", "purge_expired_audit_log", "purge_expired_contact_reveals",
          "purge_expired_erasure_fingerprints", "purge_expired_rate_limit_hits", "purge_expired_reports", "purge_expired_unmet_searches")
foreach ($f in $zero) { Check "call $f()" (Get-Status "POST" "$base/rpc/$f" "{}") $false }
$zeroUuid = "00000000-0000-0000-0000-000000000000"
$zeroHash = "0" * 64
Check "call reveal_contact(uuid)" (Get-Status "POST" "$base/rpc/reveal_contact" ('{"p_profile_id":"' + $zeroUuid + '"}')) $false
Check "call reveal_contact_limited(uuid, hash)" (Get-Status "POST" "$base/rpc/reveal_contact_limited" ('{"p_profile_id":"' + $zeroUuid + '","p_origin_hash":"' + $zeroHash + '"}')) $false
Check "call report_profile(uuid, reason)" (Get-Status "POST" "$base/rpc/report_profile" ('{"p_profile_id":"' + $zeroUuid + '","p_reason_code":"other"}')) $false
Check "call report_profile_limited(...)" (Get-Status "POST" "$base/rpc/report_profile_limited" ('{"p_profile_id":"' + $zeroUuid + '","p_reason_code":"other","p_details":"","p_reporter_email":"","p_origin_hash":"' + $zeroHash + '"}')) $false

# 6) Commit 33 functions: the three for logged-in users are refused to anon; the two for visitors answer.
#    Funciones del commit 33: las tres para usuarios con sesion se rechazan a anon; las dos para visitantes responden.
Check "call update_my_rates(jsonb)" (Get-Status "POST" "$base/rpc/update_my_rates" '{"p_rates":[]}') $false
Check "call confirm_my_rates()" (Get-Status "POST" "$base/rpc/confirm_my_rates" "{}") $false
Check "call set_profile_pinned(uuid, boolean)" (Get-Status "POST" "$base/rpc/set_profile_pinned" ('{"p_profile_id":"' + $zeroUuid + '","p_pinned":true}')) $false
Check "call rates_validity_months() (visitors)" (Get-Status "POST" "$base/rpc/rates_validity_months" "{}") $true
# therapy id 1 (the first active therapy) and location id 1 (the first country) are assumed from the seed migrations
# se asumen el id 1 de terapia (la primera activa) y el id 1 de ubicacion (el primer pais) de las migraciones de carga
Check "call search_profiles(1, 1) (visitors)" (Get-Status "POST" "$base/rpc/search_profiles" '{"p_therapy_id":1,"p_location_id":1}') $true

if ($failures -gt 0) { throw "$failures check(s) failed: do NOT publish / $failures comprobacion(es) fallaron: NO publicar." }
Write-Host "Anonymous access is as designed / El acceso anonimo es el disenado." -ForegroundColor Green
