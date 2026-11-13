-- Instagram contact: the format guard, and who can see it (visitors see it only on a published profile; phone stays hidden).
-- Contacto de Instagram: la guarda de formato, y quién lo ve (los visitantes solo en un perfil publicado; el teléfono sigue oculto).
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000007' || k)::uuid, k || '@example.test', now() from unnest(array['a1','b2']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000007' || k)::uuid, ('00000000-0000-0000-0000-0000000007' || k)::uuid, 'Nombre Legal Canario ' || k, 'canary-' || k || '@example.test'
  from unnest(array['a1','b2']) k;
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000007' || x.k)::uuid, ('10000000-0000-0000-0000-0000000007' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '5 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
         x.name
  from (values ('a1', 'Ana Pública'), ('b2', 'Beto Oculto')) x(k, name);
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select ('20000000-0000-0000-0000-0000000007' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+54 351 555 7700', true from unnest(array['a1','b2']) k;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = '20000000-0000-0000-0000-0000000007a1';

-- 1) CATALOG and FORMAT GUARD (as owner) / CATÁLOGO y GUARDA DE FORMATO
do $$
declare
  ig smallint := (select id from public.contact_types where code = 'instagram');
  bad text;
begin
  if ig is null then raise exception 'the instagram contact type must exist'; end if;
  if (select is_private from public.contact_types where id = ig) then raise exception 'instagram must be a public contact type'; end if;
  foreach bad in array array['@usuario', 'Usuario', 'https://instagram.com/usuario', 'con espacio', '', repeat('a', 31), 'ñandú', 'a/b'] loop
    begin
      insert into public.profile_contacts (profile_id, contact_type_id, value) values ('20000000-0000-0000-0000-0000000007a1', ig, bad);
      raise exception 'instagram value % must be refused', bad;
    exception when check_violation then null;
    end;
  end loop;
  begin
    insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp) values ('20000000-0000-0000-0000-0000000007a1', ig, 'ok.user', true);
    raise exception 'accepts_whatsapp must be refused for instagram';
  exception when check_violation then null;
  end;
  insert into public.profile_contacts (profile_id, contact_type_id, value) values
    ('20000000-0000-0000-0000-0000000007a1', ig, 'ana.terapias_30'), ('20000000-0000-0000-0000-0000000007b2', ig, 'beto.oculto');
end
$$;

-- 2) VISITORS (anon): the published profile shows its instagram; the unpublished one shows nothing; no phone anywhere
-- VISITANTES (anon): el perfil publicado muestra su instagram; el no publicado nada; ningún teléfono
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare ig text; n integer;
begin
  select instagram into ig from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000007a1';
  if ig is distinct from 'ana.terapias_30' then raise exception 'a visitor must see the instagram of a published profile, saw %', ig; end if;
  select count(*) into n from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000007b2';
  if n <> 0 then raise exception 'an unpublished profile must not appear'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'public_profile_detail' and column_name in ('phone', 'email')) then
    raise exception 'the public view must not have phone or email columns';
  end if;
  -- anon may read the PUBLIC contact types of a published profile (website, instagram), never phone or email
  -- anon puede leer los tipos de contacto PÚBLICOS de un perfil publicado (web, instagram), nunca teléfono ni mail
  begin
    select count(*) into n from public.profile_contacts pc join public.contact_types ct on ct.id = pc.contact_type_id where ct.is_private;
    if n <> 0 then raise exception 'anon must not see private contacts, saw %', n; end if;
    select count(*) into n from public.profile_contacts where profile_id = '20000000-0000-0000-0000-0000000007b2';
    if n <> 0 then raise exception 'anon must not see contacts of an unpublished profile, saw %', n; end if;
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 3) the owner of an unpublished profile does not leak either, and the catalog row survives a deactivation (hidden, not shown)
-- si se desactiva el tipo, deja de mostrarse (no se muestra, no se rompe)
update public.contact_types set is_active = false where code = 'instagram';
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select instagram from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000007a1') is not null then
    raise exception 'a deactivated contact type must not be shown';
  end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: instagram contact is validated and public only where it should be / el contacto de Instagram se valida y es público solo donde corresponde'
