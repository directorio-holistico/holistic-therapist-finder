-- Profile photos bucket: exists, is public, small images only, and has NO policy for anon or authenticated.
-- Bucket de fotos de perfil: existe, es público, solo imágenes chicas y NO tiene políticas para anon ni authenticated.
-- On the local database there is no "storage" schema: the check is skipped. / En la base local no hay esquema "storage": se omite.

begin;

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found: bucket checks skipped / sin esquema storage: se omiten las comprobaciones del bucket';
    return;
  end if;
  if not exists (select 1 from storage.buckets where id = 'profile-photos-public' and public = true
                   and file_size_limit = 512000 and allowed_mime_types = array['image/jpeg', 'image/webp']) then
    raise exception 'profile-photos-public bucket missing or with wrong settings';
  end if;
  -- no policy on storage.objects may name the bucket or open it to anon / authenticated
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
               and (coalesce(qual, '') like '%profile-photos-public%' or coalesce(with_check, '') like '%profile-photos-public%')) then
    raise exception 'a storage policy mentions profile-photos-public';
  end if;
end $$;

rollback;
select 'OK 31-profile-photos-bucket' as result;
