-- Removing a profile photo withdraws the photo consent of that person (and only of that person); changing the photo does not.
-- Quitar la foto de un perfil retira el consentimiento de esa persona (y solo de ella); cambiar la foto no lo retira.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test', now()),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test', now());

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.register_therapist('Ana A', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
select public.set_photo_consent(true, 'v1');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select public.register_therapist('Beto B', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
select public.set_photo_consent(true, 'v1');
reset role;
reset session authorization;

do $$
declare
  pa  uuid := (select tp.id from public.therapist_profiles tp join public.people p on p.id = tp.person_id where p.email = 'a@example.test');
  pb  uuid := (select tp.id from public.therapist_profiles tp join public.people p on p.id = tp.person_id where p.email = 'b@example.test');
  a   uuid := (select id from public.people where email = 'a@example.test');
  b   uuid := (select id from public.people where email = 'b@example.test');
  doc smallint := (select id from public.legal_document_types where code = 'photo_consent');
  other_doc smallint := (select id from public.legal_document_types where code = 'terms');
  ok  boolean;
begin
  -- the consent of each one is active / el consentimiento de cada una está activo
  if (select count(*) from public.terms_acceptances where document_type_id = doc and revoked_at is null) <> 2 then
    raise exception 'setup: both consents must be active';
  end if;

  -- setting the first photo does not touch the consent / poner la primera foto no toca el consentimiento
  update public.therapist_profiles set photo_path = pa::text || '/one.jpg' where id = pa;
  update public.therapist_profiles set photo_path = pb::text || '/one.jpg' where id = pb;
  if (select count(*) from public.terms_acceptances where document_type_id = doc and revoked_at is null) <> 2 then
    raise exception 'setting a first photo changed a consent';
  end if;

  -- changing the photo for another one does not touch the consent / cambiar la foto por otra no toca el consentimiento
  update public.therapist_profiles set photo_path = pa::text || '/two.jpg' where id = pa;
  if (select count(*) from public.terms_acceptances where document_type_id = doc and revoked_at is null) <> 2 then
    raise exception 'replacing the photo changed a consent';
  end if;

  -- another column does not touch it / otra columna no lo toca
  update public.therapist_profiles set headline = 'Reiki' where id = pa;
  if (select count(*) from public.terms_acceptances where document_type_id = doc and revoked_at is null) <> 2 then
    raise exception 'editing another column changed a consent';
  end if;

  -- REMOVING A's photo through the real path (the payload of an approved revision) withdraws A's consent only
  -- QUITAR la foto de A por el camino real (el contenido de una revisión aprobada) retira solo el consentimiento de A
  perform public.apply_revision_payload(pa, '{"photo_path": null}'::jsonb);
  if (select photo_path from public.therapist_profiles where id = pa) is not null then raise exception 'the photo was not removed'; end if;
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = doc and revoked_at is null) <> 0 then
    raise exception 'the consent of A is still active after removing the photo';
  end if;
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = doc) <> 1 then
    raise exception 'the history of A was deleted instead of kept';
  end if;
  if (select count(*) from public.terms_acceptances where person_id = b and document_type_id = doc and revoked_at is null) <> 1 then
    raise exception 'removing the photo of A changed the consent of B';
  end if;
  -- the required documents of A are untouched / los documentos obligatorios de A no se tocan
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = other_doc and revoked_at is null) <> 1 then
    raise exception 'a required document of A was revoked';
  end if;

  -- removing again, with no photo and no active consent: no error and no change / quitar otra vez: sin error y sin cambio
  perform public.apply_revision_payload(pa, '{"photo_path": null}'::jsonb);

  -- giving the consent again after the removal works and a later removal withdraws it again
  -- dar el consentimiento de nuevo tras la quita funciona, y una quita posterior lo retira otra vez
  set role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  perform public.set_photo_consent(true, 'v2');
  reset role;
  reset session authorization;
  update public.therapist_profiles set photo_path = pa::text || '/three.jpg' where id = pa;
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = doc and revoked_at is null) <> 1 then
    raise exception 'the new consent of A is not active';
  end if;
  perform public.apply_revision_payload(pa, '{"photo_path": null}'::jsonb);
  if (select count(*) from public.terms_acceptances where person_id = a and document_type_id = doc and revoked_at is null) <> 0 then
    raise exception 'the second removal did not withdraw the consent';
  end if;

end
$$;

-- API roles cannot execute the trigger function / los roles de la API no pueden ejecutar la función del trigger
do $$
declare r text; denied boolean;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(r, 'public.revoke_photo_consent_on_removal()', 'execute') then
      raise exception '% can execute revoke_photo_consent_on_removal', r;
    end if;
  end loop;
end
$$;

-- the trigger exists once and fires only on photo_path / el trigger existe una vez y se dispara solo con photo_path
do $$
begin
  if (select count(*) from pg_trigger where tgname = 'therapist_profiles_photo_removed' and not tgisinternal) <> 1 then
    raise exception 'expected exactly one photo-removed trigger';
  end if;
end
$$;

select 'OK 33-photo-consent-revocation' as result;

rollback;
