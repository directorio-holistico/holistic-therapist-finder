-- Read-only checks for the REAL project after applying 20261116030000 / Solo lectura, proyecto REAL.
-- Private bucket for pending photos and the photo consent document. SECURITY CHANGE: private bucket, 1 catalog row, 1 function.
-- Bucket privado de fotos pendientes y documento de consentimiento de la foto. CAMBIO DE SEGURIDAD.

-- 1) The private bucket. Expected / Esperado: profile-photos-pending | false | 512000 | {image/jpeg,image/webp}
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'profile-photos-pending';

-- 2) No policy mentions it. Expected / Esperado: 0 rows
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and (coalesce(qual, '') like '%profile-photos-pending%' or coalesce(with_check, '') like '%profile-photos-pending%');

-- 3) The document is optional and active. Expected / Esperado: photo_consent | false | true | 5
select code, is_required, is_active, sort_order from public.legal_document_types where code = 'photo_consent';

-- 4) Grants of the function. Expected / Esperado: anon = false | authenticated = true | service_role = false
select has_function_privilege('anon', 'public.set_photo_consent(boolean,text)', 'execute') as anon,
       has_function_privilege('authenticated', 'public.set_photo_consent(boolean,text)', 'execute') as authenticated,
       has_function_privilege('service_role', 'public.set_photo_consent(boolean,text)', 'execute') as service_role;

-- 5) The function is security definer with a fixed search_path. Expected / Esperado: true | {search_path=pg_catalog, public}
select p.prosecdef as security_definer, p.proconfig from pg_proc p where p.oid = 'public.set_photo_consent(boolean,text)'::regprocedure;

-- 6) Nothing else changed in the required documents. Expected / Esperado: 3
select count(*) as required_documents from public.legal_document_types where is_required;
