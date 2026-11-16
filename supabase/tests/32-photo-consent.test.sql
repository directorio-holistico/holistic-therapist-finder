-- Photo consent: optional document, give / withdraw, history, isolation between people, grants; private bucket (if storage exists).
-- Consentimiento de la foto: documento opcional, dar / retirar, historia, aislamiento entre personas, permisos; bucket privado.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test', now()),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test', now()),
  ('00000000-0000-0000-0000-0000000000f6', 'f@example.test', now());   -- never registers

-- 1) The document exists, is optional and active; registering still needs only the required ones (as owner)
do $$
begin
  if not exists (select 1 from public.legal_document_types where code = 'photo_consent' and is_required = false and is_active) then
    raise exception 'photo_consent missing, required or inactive';
  end if;
  if (select count(*) from public.legal_document_types where is_required) <> 3 then raise exception 'expected 3 required documents'; end if;
end
$$;

-- 2) A and B register WITHOUT the photo consent: it is optional / A y B se registran SIN el consentimiento: es opcional
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.register_therapist('Ana A', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select public.register_therapist('Beto B', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
reset role;
reset session authorization;

-- 3) A gives, repeats, withdraws and gives again / A da, repite, retira y vuelve a dar
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare ok boolean; me uuid := public.current_person_id();
  doc smallint := (select id from public.legal_document_types where code = 'photo_consent');
begin
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc) <> 0 then
    raise exception 'registering created a photo consent by itself';
  end if;
  ok := false; begin perform public.set_photo_consent(true, null); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'consent without a version was accepted'; end if;
  ok := false; begin perform public.set_photo_consent(true, 'bad version'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'consent with an invalid version was accepted'; end if;
  ok := false; begin perform public.set_photo_consent(null, 'v1'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a null value was accepted'; end if;
  perform public.set_photo_consent(true, 'v1');
  perform public.set_photo_consent(true, 'v1');  -- same version already active: no duplicate
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc) <> 1 then raise exception 'a duplicate consent was created'; end if;
  perform public.set_photo_consent(true, 'v2');  -- a new text: its own row; the old one stays as history
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc and revoked_at is null) <> 2 then
    raise exception 'a new version must add its own active row';
  end if;
  perform public.set_photo_consent(false);       -- withdraw: every active row is revoked, none is deleted
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc) <> 2
     or (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc and revoked_at is null) <> 0 then
    raise exception 'withdrawing must revoke every active row and keep the history';
  end if;
  perform public.set_photo_consent(false);      -- nothing to revoke: no error
  perform public.set_photo_consent(true, 'v2'); -- give again after withdrawing
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = doc and revoked_at is null) <> 1 then
    raise exception 'giving again after withdrawing must create an active row';
  end if;
  -- nobody writes the evidence through the API / nadie escribe la evidencia por la API
  ok := false;
  begin insert into public.terms_acceptances (person_id, document_type_id, version) values (me, doc, 'v9'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist inserted evidence directly'; end if;
end
$$;
reset role;
reset session authorization;

-- 4) B sees none of A's evidence, and B's own consent is separate / B no ve la evidencia de A
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
declare doc smallint := (select id from public.legal_document_types where code = 'photo_consent');
begin
  if (select count(*) from public.terms_acceptances where document_type_id = doc) <> 0 then raise exception 'B sees the photo consent of A'; end if;
  perform public.set_photo_consent(false);  -- B withdrawing must not touch A's rows
end
$$;
reset role;
reset session authorization;
do $$
declare a uuid := (select id from public.people where email = 'a@example.test');
  doc smallint := (select id from public.legal_document_types where code = 'photo_consent');
begin
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = doc and revoked_at is null) <> 1 then
    raise exception 'the call of B changed the consent of A';
  end if;
end
$$;

-- 5) F is logged in but has no person: no consent / F tiene sesión pero no ficha
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f6","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.set_photo_consent(true, 'v1'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a login without a person gave a consent'; end if;
end
$$;
reset role;
reset session authorization;

-- 6) Anonymous: cannot call it / Anónimo: no puede llamarla
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare denied boolean := false;
begin
  begin perform public.set_photo_consent(true, 'v1'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon could give a photo consent'; end if;
end
$$;
reset role;
reset session authorization;

-- 7) Grants and the private bucket (when the storage schema exists) / Permisos y bucket privado (si existe storage)
do $$
begin
  if not has_function_privilege('authenticated', 'public.set_photo_consent(boolean,text)', 'EXECUTE') then raise exception 'authenticated cannot execute set_photo_consent'; end if;
  if has_function_privilege('anon', 'public.set_photo_consent(boolean,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.set_photo_consent(boolean,text)', 'EXECUTE') then
    raise exception 'anon or service_role can execute set_photo_consent';
  end if;
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found: bucket checks skipped / sin esquema storage: se omiten las comprobaciones del bucket';
    return;
  end if;
  if not exists (select 1 from storage.buckets where id = 'profile-photos-pending' and public = false
                   and file_size_limit = 512000 and allowed_mime_types = array['image/jpeg', 'image/webp']) then
    raise exception 'profile-photos-pending bucket missing or with wrong settings';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
               and (coalesce(qual, '') like '%profile-photos-pending%' or coalesce(with_check, '') like '%profile-photos-pending%')) then
    raise exception 'a storage policy mentions profile-photos-pending';
  end if;
end
$$;

rollback;
select 'OK 32-photo-consent' as result;
