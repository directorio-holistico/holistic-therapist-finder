-- Read-only checks for the REAL project after applying 20261116020000 / Solo lectura, proyecto REAL.
-- Public bucket for profile photos. SECURITY CHANGE: public bucket without policies.
-- Bucket público de fotos de perfil. CAMBIO DE SEGURIDAD: bucket público sin políticas.

-- 1) The bucket exists, is public, 500 KB, JPEG and WebP only.
--    Expected / Esperado: profile-photos-public | true | 512000 | {image/jpeg,image/webp}
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'profile-photos-public';

-- 2) No policy mentions the bucket. Expected / Esperado: 0 rows
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and (coalesce(qual, '') like '%profile-photos-public%' or coalesce(with_check, '') like '%profile-photos-public%');

-- 3) Row security is on for storage.objects. Expected / Esperado: true
select relrowsecurity from pg_class where oid = 'storage.objects'::regclass;

-- 4) How many policies exist in storage.objects at all (should be only the ones you know). Expected / Esperado: 0 (nothing was there before)
select count(*) as policies_on_storage_objects from pg_policies where schemaname = 'storage' and tablename = 'objects';
