-- Facebook, TikTok and YouTube contacts: the link guard, and who can see them (visitors see them only on a published profile).
-- Contactos de Facebook, TikTok y YouTube: la guarda del enlace, y quién los ve (los visitantes solo en un perfil publicado).
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000008' || k)::uuid, k || '@example.test', now() from unnest(array['a1','b2']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000008' || k)::uuid, ('00000000-0000-0000-0000-0000000008' || k)::uuid, 'Nombre Legal Canario ' || k, 'canary-' || k || '@example.test'
  from unnest(array['a1','b2']) k;
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000008' || x.k)::uuid, ('10000000-0000-0000-0000-0000000008' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '5 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
         x.name
  from (values ('a1', 'Ana Pública'), ('b2', 'Beto Oculto')) x(k, name);
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select ('20000000-0000-0000-0000-0000000008' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+54 351 555 8800', true from unnest(array['a1','b2']) k;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = '20000000-0000-0000-0000-0000000008a1';

-- 1) CATALOG and LINK GUARD (as owner) / CATÁLOGO y GUARDA DE ENLACES
do $$
declare
  t record;
  bad text;
  good text;
begin
  for t in select * from (values
    ('facebook', array['http://www.facebook.com/ana', 'https://facebook.com.evil.test/ana', 'https://evil.test/facebook.com/ana', 'https://facebook.com@evil.test/ana', 'https://www.facebook.com/', 'https://www.facebook.com/a b', 'ana', '', 'https://www.instagram.com/ana'], 'https://www.facebook.com/ana.terapias'),
    ('tiktok', array['@ana.terapias', 'https://www.tiktok.com/@a', 'https://www.tiktok.com/@ana.terapias/video/1', 'https://vm.tiktok.com/abc', 'https://tiktok.com.evil.test/@ana', 'http://www.tiktok.com/@ana.terapias', 'https://www.tiktok.com/@' || repeat('a', 25)], 'https://www.tiktok.com/@ana.terapias'),
    ('youtube', array['https://www.youtube.com/watch?v=abc', 'https://youtu.be/abc', 'https://www.youtube.com/@ab', 'https://youtube.com.evil.test/@ana', 'http://www.youtube.com/@ana', '@anaterapias', 'https://www.youtube.com/channel/UCshort'], 'https://www.youtube.com/@anaterapias')
  ) v(code, bads, good)
  loop
    if not exists (select 1 from public.contact_types where code = t.code and is_private = false and is_active) then
      raise exception '% must exist as a public contact type', t.code;
    end if;
    foreach bad in array t.bads loop
      begin
        insert into public.profile_contacts (profile_id, contact_type_id, value) values
          ('20000000-0000-0000-0000-0000000008a1', (select id from public.contact_types where code = t.code), bad);
        raise exception '% value % must be refused', t.code, bad;
      exception when check_violation then null;
      end;
    end loop;
    begin
      insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp) values
        ('20000000-0000-0000-0000-0000000008a1', (select id from public.contact_types where code = t.code), t.good, true);
      raise exception 'accepts_whatsapp must be refused for %', t.code;
    exception when check_violation then null;
    end;
    insert into public.profile_contacts (profile_id, contact_type_id, value) values
      ('20000000-0000-0000-0000-0000000008a1', (select id from public.contact_types where code = t.code), t.good),
      ('20000000-0000-0000-0000-0000000008b2', (select id from public.contact_types where code = t.code), t.good || 'x');
  end loop;
  -- the other two accepted shapes of YouTube / las otras dos formas válidas de YouTube
  foreach good in array array['https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv', 'https://www.youtube.com/c/AnaTerapias', 'https://m.youtube.com/user/anaterapias/'] loop
    update public.profile_contacts set value = good
      where profile_id = '20000000-0000-0000-0000-0000000008b2' and contact_type_id = (select id from public.contact_types where code = 'youtube');
  end loop;
end
$$;

-- 2) VISITORS (anon): the published profile shows its three links; the unpublished one nothing; private contacts never
-- VISITANTES (anon): el perfil publicado muestra sus tres enlaces; el no publicado nada; los contactos privados nunca
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare d record; n integer;
begin
  select facebook, tiktok, youtube into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000008a1';
  if d.facebook is distinct from 'https://www.facebook.com/ana.terapias' then raise exception 'a visitor must see the facebook of a published profile, saw %', d.facebook; end if;
  if d.tiktok is distinct from 'https://www.tiktok.com/@ana.terapias' then raise exception 'a visitor must see the tiktok of a published profile, saw %', d.tiktok; end if;
  if d.youtube is distinct from 'https://www.youtube.com/@anaterapias' then raise exception 'a visitor must see the youtube of a published profile, saw %', d.youtube; end if;
  select count(*) into n from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000008b2';
  if n <> 0 then raise exception 'an unpublished profile must not appear'; end if;
  begin
    select count(*) into n from public.profile_contacts pc join public.contact_types ct on ct.id = pc.contact_type_id where ct.is_private;
    if n <> 0 then raise exception 'anon must not see private contacts, saw %', n; end if;
    select count(*) into n from public.profile_contacts where profile_id = '20000000-0000-0000-0000-0000000008b2';
    if n <> 0 then raise exception 'anon must not see contacts of an unpublished profile, saw %', n; end if;
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 3) a deactivated type stops being shown (hidden, not broken) / un tipo desactivado deja de mostrarse (no se muestra, no se rompe)
update public.contact_types set is_active = false where code in ('facebook', 'tiktok', 'youtube');
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare d record;
begin
  select facebook, tiktok, youtube into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000008a1';
  if d.facebook is not null or d.tiktok is not null or d.youtube is not null then raise exception 'a deactivated contact type must not be shown'; end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: facebook, tiktok and youtube contacts are validated and public only where they should be / los contactos de Facebook, TikTok y YouTube se validan y son públicos solo donde corresponde'
