-- Migration: service modes and session formats belong to each THERAPY, not to the whole profile.
-- Migración: la modalidad y el formato de sesión pertenecen a cada TERAPIA, no a todo el perfil.
--
-- Owner decision 14/11/2026: a therapist may give massages in person, LNT in person and remote, Reiki remote only.
-- Decisión del titular (14/11/2026): un terapeuta puede dar masajes presencial, LNT presencial y a distancia, Reiki a distancia.
--
-- What changes / Qué cambia:
--  1. Two new tables replace profile_service_modes and profile_session_formats: one row per (profile, therapy, mode|format).
--     Dos tablas nuevas reemplazan a profile_service_modes y profile_session_formats: una fila por (perfil, terapia, modalidad|formato).
--  2. Every therapy needs AT LEAST ONE mode and ONE format: a deferred constraint trigger (checked at the end of the transaction).
--     Toda terapia necesita AL MENOS UNA modalidad y UN formato: trigger de restricción diferido (se revisa al final de la transacción).
--  3. The old data is copied to every therapy of its profile ("they inherit"), open revisions are converted, old tables dropped.
--     Los datos viejos se copian a cada terapia de su perfil ("heredan"), las revisiones abiertas se convierten, se borran las tablas viejas.
--  4. The revision payload carries service_modes and session_formats INSIDE each therapy; the profile-level keys no longer exist.
--     El payload de la revisión lleva service_modes y session_formats DENTRO de cada terapia; las claves del perfil ya no existen.
--  5. The public card shows the UNION of all the therapies; the search looks only at the modes of the SEARCHED therapy.
--     La tarjeta pública muestra la UNIÓN de todas las terapias; la búsqueda mira solo las modalidades de la terapia BUSCADA.
--
-- Public reads (anon), listed in writing / Lecturas públicas (anon), por escrito:
--   profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)     rows: of published profiles only
--   profile_therapy_session_formats (profile_id, therapy_id, session_format_id) rows: of published profiles only
-- Writes: nobody through the API; only the approval function (same as the other child tables of a profile).
-- Escrituras: nadie por la API; solo la función de aprobación (igual que las demás tablas hijas del perfil).

-- ============================================================================
-- 1. New tables / Tablas nuevas
-- ============================================================================
create table public.profile_therapy_service_modes (
  profile_id      uuid     not null,
  therapy_id      integer  not null,
  service_mode_id smallint not null references public.service_modes (id) on delete restrict,
  primary key (profile_id, therapy_id, service_mode_id),
  foreign key (profile_id, therapy_id) references public.profile_therapies (profile_id, therapy_id) on delete cascade
);
create index profile_therapy_service_modes_therapy_idx on public.profile_therapy_service_modes (therapy_id, service_mode_id);
comment on table public.profile_therapy_service_modes is
  'Service modes (in person, remote) of one therapy of a profile; at least one per therapy / Modalidades de una terapia de un perfil; al menos una por terapia.';

create table public.profile_therapy_session_formats (
  profile_id        uuid     not null,
  therapy_id        integer  not null,
  session_format_id smallint not null references public.session_formats (id) on delete restrict,
  primary key (profile_id, therapy_id, session_format_id),
  foreign key (profile_id, therapy_id) references public.profile_therapies (profile_id, therapy_id) on delete cascade
);
create index profile_therapy_session_formats_therapy_idx on public.profile_therapy_session_formats (therapy_id, session_format_id);
comment on table public.profile_therapy_session_formats is
  'Session formats (individual, group) of one therapy of a profile; at least one per therapy / Formatos de sesión de una terapia de un perfil; al menos uno por terapia.';

-- ============================================================================
-- 2. The old profile-level data is inherited by every therapy of the profile / Los datos viejos los heredan todas las terapias
-- ============================================================================
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
  select pt.profile_id, pt.therapy_id, x.service_mode_id
  from public.profile_therapies pt
  join public.profile_service_modes x on x.profile_id = pt.profile_id;

insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id)
  select pt.profile_id, pt.therapy_id, x.session_format_id
  from public.profile_therapies pt
  join public.profile_session_formats x on x.profile_id = pt.profile_id;

-- Open revisions (draft or pending): the two profile-level lists move INSIDE each therapy of the payload. A closed revision
-- is history and is never applied again, so it stays as it was. Without "therapies" in the payload the lists have no place to go.
-- Revisiones abiertas (borrador o en revisión): las dos listas del perfil pasan DENTRO de cada terapia del payload. Una revisión
-- cerrada es historia y no se vuelve a aplicar, así que queda como estaba. Sin "therapies" en el payload las listas no tienen dónde ir.
update public.profile_revisions r
   set payload = (r.payload - 'service_modes' - 'session_formats')
     || case
          when jsonb_typeof(r.payload -> 'therapies') = 'array' then
            jsonb_build_object('therapies', coalesce((
              select jsonb_agg(t || jsonb_build_object(
                       'service_modes',   coalesce(r.payload -> 'service_modes', '[]'::jsonb),
                       'session_formats', coalesce(r.payload -> 'session_formats', '[]'::jsonb)))
              from jsonb_array_elements(r.payload -> 'therapies') t
              where jsonb_typeof(t) = 'object'), '[]'::jsonb))
          else '{}'::jsonb
        end
 where r.closed_at is null
   and (r.payload ? 'service_modes' or r.payload ? 'session_formats');

-- ============================================================================
-- 3. SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================
do $$
declare
  t text;
begin
  foreach t in array array['profile_therapy_service_modes', 'profile_therapy_session_formats'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format($p$create policy %I on public.%I for select to authenticated
      using (exists (select 1 from public.therapist_profiles tp
                     where tp.id = profile_id and tp.person_id = (select public.current_person_id())))$p$,
      t || '_select_own', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_admin()))',
      t || '_select_admin', t);
    execute format('create policy %I on public.%I for select to anon using (public.is_published_profile(profile_id))',
      t || '_select_public', t);
  end loop;
end
$$;
grant select (profile_id, therapy_id, service_mode_id) on public.profile_therapy_service_modes to anon;
grant select (profile_id, therapy_id, session_format_id) on public.profile_therapy_session_formats to anon;

-- ============================================================================
-- 4. "At least one mode and one format per therapy" (checked at the END of the transaction)
--    "Al menos una modalidad y un formato por terapia" (se revisa al FINAL de la transacción)
-- ============================================================================
create function public.profile_therapy_options_check()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  p uuid;
  t integer;
begin
  if tg_op = 'DELETE' then
    p := old.profile_id; t := old.therapy_id;
  else
    p := new.profile_id; t := new.therapy_id;
  end if;
  -- the therapy itself was removed (the children went with it): nothing to check / se quitó la terapia: no hay nada que revisar
  if not exists (select 1 from public.profile_therapies where profile_id = p and therapy_id = t) then
    return null;
  end if;
  if not exists (select 1 from public.profile_therapy_service_modes where profile_id = p and therapy_id = t) then
    raise exception 'each therapy needs at least one service mode' using errcode = '23514';
  end if;
  if not exists (select 1 from public.profile_therapy_session_formats where profile_id = p and therapy_id = t) then
    raise exception 'each therapy needs at least one session format' using errcode = '23514';
  end if;
  return null;
end
$$;
revoke execute on function public.profile_therapy_options_check() from public, anon, authenticated, service_role;

create constraint trigger profile_therapies_options_check
  after insert on public.profile_therapies
  deferrable initially deferred for each row execute function public.profile_therapy_options_check();
create constraint trigger profile_therapy_service_modes_options_check
  after delete on public.profile_therapy_service_modes
  deferrable initially deferred for each row execute function public.profile_therapy_options_check();
create constraint trigger profile_therapy_session_formats_options_check
  after delete on public.profile_therapy_session_formats
  deferrable initially deferred for each row execute function public.profile_therapy_options_check();

-- ============================================================================
-- 5. Public views: same columns, new source / Vistas públicas: mismas columnas, nueva fuente
-- ============================================================================
create or replace view public.public_profile_cards with (security_invoker = true) as
select
  tp.id                      as profile_id,
  tp.display_name,
  tp.photo_path,
  tp.headline,
  tp.zone,
  tp.approved_at,
  tp.location_id             as city_id,
  city_t.name                as city_name,
  anc.region_id,
  region_t.name              as region_name,
  anc.country_id,
  country_t.name             as country_name,
  country.iso_code           as country_iso,
  coalesce(th.therapy_ids, '{}')    as therapy_ids,
  coalesce(th.therapy_names, '{}')  as therapy_names,
  coalesce(sm.codes, '{}')   as service_modes,
  coalesce(sf.codes, '{}')   as session_formats,
  coalesce(lg.codes, '{}')   as languages,
  coalesce(rt.rates_from, '{}'::jsonb) as rates_from,
  -- new columns go at the END (create or replace view cannot insert columns in the middle)
  -- las columnas nuevas van AL FINAL (create or replace view no permite insertar columnas en el medio)
  tp.rates_confirmed_at,
  (rt.rates_from is not null and rt.rates_from <> '{}'::jsonb
   and tp.rates_confirmed_at is not null
   and tp.rates_confirmed_at >= now() - make_interval(months => public.rates_validity_months())) as rates_current,
  tp.is_pinned
from public.therapist_profiles tp
cross join lateral (select l.id from public.languages l where l.code = 'es') es
left join lateral (
  with recursive up as (
    select l.id, l.parent_id, l.level_id from public.locations l where l.id = tp.location_id
    union all
    select l.id, l.parent_id, l.level_id from public.locations l join up on l.id = up.parent_id
  )
  select max(up.id) filter (where ll.code = 'region')  as region_id,
         max(up.id) filter (where ll.code = 'country') as country_id
  from up join public.location_levels ll on ll.id = up.level_id
) anc on true
left join public.location_translations city_t on city_t.location_id = tp.location_id and city_t.language_id = es.id
left join public.location_translations region_t on region_t.location_id = anc.region_id and region_t.language_id = es.id
left join public.locations country on country.id = anc.country_id
left join public.location_translations country_t on country_t.location_id = anc.country_id and country_t.language_id = es.id
left join lateral (
  select array_agg(t.id order by t.id) as therapy_ids, array_agg(coalesce(tt.name, t.code) order by t.id) as therapy_names
  from public.profile_therapies pt
  join public.therapies t on t.id = pt.therapy_id and t.is_active
  left join public.therapy_translations tt on tt.therapy_id = t.id and tt.language_id = es.id
  where pt.profile_id = tp.id
) th on true
left join lateral (
  -- union of the modes of all the (active) therapies / unión de las modalidades de todas las terapias (activas)
  select array_agg(m.code order by m.sort_order, m.id) as codes
  from public.service_modes m
  where m.is_active and exists (
    select 1 from public.profile_therapy_service_modes x
    join public.therapies t on t.id = x.therapy_id and t.is_active
    where x.profile_id = tp.id and x.service_mode_id = m.id)
) sm on true
left join lateral (
  -- union of the formats of all the (active) therapies / unión de los formatos de todas las terapias (activas)
  select array_agg(f.code order by f.sort_order, f.id) as codes
  from public.session_formats f
  where f.is_active and exists (
    select 1 from public.profile_therapy_session_formats x
    join public.therapies t on t.id = x.therapy_id and t.is_active
    where x.profile_id = tp.id and x.session_format_id = f.id)
) sf on true
left join lateral (
  select array_agg(l.code order by l.sort_order, l.id) as codes
  from public.profile_languages x join public.languages l on l.id = x.language_id and l.is_active
  where x.profile_id = tp.id
) lg on true
left join lateral (
  -- "from" rate per audience: the lowest amount, with its currency (one currency per audience in a profile)
  -- tarifa "desde" por audiencia: el monto más bajo, con su moneda (una moneda por audiencia en el perfil)
  select jsonb_object_agg(x.audience, jsonb_build_object('amount', x.min_amount, 'currency', x.currency)) as rates_from
  from (
    select a.code as audience, c.code as currency, min(r.amount) as min_amount
    from public.profile_therapy_rates r
    join public.therapies t on t.id = r.therapy_id and t.is_active
    join public.rate_audiences a on a.id = r.rate_audience_id and a.is_active
    join public.currencies c on c.id = r.currency_id
    where r.profile_id = tp.id
    group by a.code, c.code
  ) x
) rt on true
where public.is_published_profile(tp.id);

-- The detail view keeps its columns; each therapy of "therapies_detail" now carries its own modes and formats.
-- La vista de detalle conserva sus columnas; cada terapia de "therapies_detail" trae ahora sus modalidades y formatos.
create or replace view public.public_profile_detail with (security_invoker = true) as
select
  c.*,
  tp.practice_start_year,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'website') as website,
  coalesce((
    select jsonb_agg(jsonb_build_object(
             'therapy_id', t.id,
             'name', coalesce(tt.name, t.code),
             'session_minutes', pt.session_minutes,
             'service_modes', coalesce((
               select jsonb_agg(m.code order by m.sort_order, m.id)
               from public.profile_therapy_service_modes x
               join public.service_modes m on m.id = x.service_mode_id and m.is_active
               where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id), '[]'::jsonb),
             'session_formats', coalesce((
               select jsonb_agg(f.code order by f.sort_order, f.id)
               from public.profile_therapy_session_formats x
               join public.session_formats f on f.id = x.session_format_id and f.is_active
               where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id), '[]'::jsonb),
             'rates', coalesce((
               select jsonb_agg(jsonb_build_object('audience', a.code, 'amount', r.amount, 'currency', cu.code) order by a.sort_order, a.id)
               from public.profile_therapy_rates r
               join public.rate_audiences a on a.id = r.rate_audience_id and a.is_active
               join public.currencies cu on cu.id = r.currency_id
               where r.profile_id = pt.profile_id and r.therapy_id = pt.therapy_id), '[]'::jsonb))
           order by t.id)
    from public.profile_therapies pt
    join public.therapies t on t.id = pt.therapy_id and t.is_active
    left join public.therapy_translations tt on tt.therapy_id = t.id and tt.language_id = (select l.id from public.languages l where l.code = 'es')
    where pt.profile_id = c.profile_id), '[]'::jsonb) as therapies_detail,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'instagram') as instagram,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'facebook') as facebook,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'tiktok') as tiktok,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'youtube') as youtube
from public.public_profile_cards c
join public.therapist_profiles tp on tp.id = c.profile_id;

comment on view public.public_profile_cards is 'Search result card of a published profile; no phone, no email / Tarjeta de resultado de un perfil publicado; sin teléfono ni mail.';
comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';

-- ============================================================================
-- 6. Functions: approval applies the lists per therapy; the search looks at the searched therapy only
--    Funciones: la aprobación aplica las listas por terapia; la búsqueda mira solo la terapia buscada
--    (same signatures, so permissions are kept / mismas firmas, así que se conservan los permisos)
-- ============================================================================
-- submit_revision: the allowed top-level keys no longer include the two lists. / ya no admite las dos listas en el nivel superior.
create or replace function public.submit_revision(p_revision_id uuid)
returns text[]
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person        uuid := public.current_person_id();
  rev           public.profile_revisions%rowtype;
  profile_row   public.therapist_profiles%rowtype;
  profile_status text;
  draft_id      smallint;
  pending_id    smallint;
  allowed_keys  constant text[] := array['display_name', 'headline', 'zone', 'practice_start_year', 'location_id',
                                          'photo_path', 'therapies', 'languages', 'contacts'];
  unknown_keys  text[];
  all_text      text;
  flagged       text[];
  days_setting  text;
  days          integer;
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;

  select r.* into rev
    from public.profile_revisions r
    join public.therapist_profiles tp on tp.id = r.profile_id
    where r.id = p_revision_id and tp.person_id = person
    for update of r;
  if not found then
    raise exception 'revision not found' using errcode = 'P0002';
  end if;

  select id into strict draft_id from public.revision_statuses where code = 'draft';
  select id into strict pending_id from public.revision_statuses where code = 'pending_review';
  if rev.status_id <> draft_id then
    raise exception 'only a draft can be submitted' using errcode = '55000';
  end if;

  select * into profile_row from public.therapist_profiles where id = rev.profile_id;
  select code into strict profile_status from public.profile_statuses where id = profile_row.status_id;
  if profile_status in ('suspended', 'erased') then
    raise exception 'a % profile cannot submit revisions', profile_status using errcode = '55000';
  end if;

  -- the payload must have content and only known top-level keys (full validation happens when it is approved)
  -- el payload debe tener contenido y solo claves conocidas (la validación completa ocurre al aprobarlo)
  if rev.payload = '{}'::jsonb then
    raise exception 'the revision is empty' using errcode = '22023';
  end if;
  select array_agg(k) into unknown_keys from jsonb_object_keys(rev.payload) k where k <> all (allowed_keys);
  if unknown_keys is not null then
    raise exception 'unknown payload keys: %', unknown_keys using errcode = '22023';
  end if;

  -- every text in the payload plus the suggested therapy is checked against the restricted terms
  -- cada texto del payload más la terapia sugerida se compara con los términos restringidos
  select concat_ws(' ',
           (select string_agg(v #>> '{}', ' ') from jsonb_path_query(rev.payload, 'strict $.**') v
             where jsonb_typeof(v) = 'string'),
           rev.suggested_therapy)
    into all_text;
  flagged := public.match_restricted_terms(all_text);

  select case
           when rev.is_priority then 'review_days_priority'
           when profile_row.approved_at is null then 'review_days_initial'
           else 'review_days_update'
         end
    into days_setting;
  select (value::text)::int into days from public.app_settings where key = days_setting;
  if days is null then
    raise exception 'setting % is missing', days_setting using errcode = '23514';
  end if;

  update public.profile_revisions
     set status_id = pending_id,
         flagged_terms = flagged,
         submitted_at = now(),
         due_at = public.add_business_days(now(), days)
   where id = rev.id;
  return flagged;
end
$$;

-- apply_revision_payload: each therapy of the payload carries its own non-empty "service_modes" and "session_formats".
-- apply_revision_payload: cada terapia del payload trae sus "service_modes" y "session_formats" no vacías.
create or replace function public.apply_revision_payload(p_profile_id uuid, p_payload jsonb)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  elem   jsonb;
  opt    jsonb;
  rate   jsonb;
  v      integer;
  tid    integer;
  mins   integer;
  types  integer[];
  photo  text;
  max_items constant integer := 50;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'the payload must be an object' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) k
             where k <> all (array['display_name', 'headline', 'zone', 'practice_start_year', 'location_id', 'photo_path',
                                   'therapies', 'languages', 'contacts'])) then
    raise exception 'the payload has unknown keys' using errcode = '22023';
  end if;

  -- text scalars / escalares de texto
  if p_payload ? 'display_name' then
    if jsonb_typeof(p_payload -> 'display_name') not in ('string', 'null') then
      raise exception 'display_name must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set display_name = p_payload ->> 'display_name' where id = p_profile_id;
  end if;
  if p_payload ? 'headline' then
    if jsonb_typeof(p_payload -> 'headline') not in ('string', 'null') then
      raise exception 'headline must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set headline = p_payload ->> 'headline' where id = p_profile_id;
  end if;
  if p_payload ? 'zone' then
    if jsonb_typeof(p_payload -> 'zone') not in ('string', 'null') then
      raise exception 'zone must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set zone = p_payload ->> 'zone' where id = p_profile_id;
  end if;
  if p_payload ? 'photo_path' then
    if jsonb_typeof(p_payload -> 'photo_path') not in ('string', 'null') then
      raise exception 'photo_path must be text or null' using errcode = '22023';
    end if;
    photo := p_payload ->> 'photo_path';
    if photo is not null and (left(photo, 37) <> p_profile_id::text || '/'
                              or photo !~ '^[A-Za-z0-9/_.-]+$' or photo like '%..%') then
      raise exception 'photo_path must be a clean path under the profile folder' using errcode = '22023';
    end if;
    update public.therapist_profiles set photo_path = photo where id = p_profile_id;
  end if;

  -- numeric scalars / escalares numéricos
  if p_payload ? 'practice_start_year' then
    if jsonb_typeof(p_payload -> 'practice_start_year') = 'null' then
      update public.therapist_profiles set practice_start_year = null where id = p_profile_id;
    else
      update public.therapist_profiles
         set practice_start_year = public.revision_int(p_payload -> 'practice_start_year', 'practice_start_year')
       where id = p_profile_id;
    end if;
  end if;
  if p_payload ? 'location_id' then
    if jsonb_typeof(p_payload -> 'location_id') = 'null' then
      update public.therapist_profiles set location_id = null where id = p_profile_id;
    else
      v := public.revision_int(p_payload -> 'location_id', 'location_id');
      if not exists (select 1 from public.locations where id = v and is_active) then
        raise exception 'unknown or inactive location' using errcode = '22023';
      end if;
      update public.therapist_profiles set location_id = v where id = p_profile_id;  -- the guard requires a city
    end if;
  end if;

  -- simple lists / listas simples
  if p_payload ? 'languages' then
    if jsonb_typeof(p_payload -> 'languages') <> 'array' or jsonb_array_length(p_payload -> 'languages') > max_items then
      raise exception 'languages must be a list of at most % ids', max_items using errcode = '22023';
    end if;
    delete from public.profile_languages where profile_id = p_profile_id;
    for elem in select value from jsonb_array_elements(p_payload -> 'languages') loop
      v := public.revision_int(elem, 'language id');
      if not exists (select 1 from public.languages where id = v and is_active) then
        raise exception 'unknown or inactive language' using errcode = '22023';
      end if;
      insert into public.profile_languages (profile_id, language_id) values (p_profile_id, v);
    end loop;
  end if;

  -- therapies with their rates (the limit and the currency rules are enforced by the table triggers)
  -- terapias con sus tarifas (el límite y las reglas de moneda las hacen los triggers de las tablas)
  if p_payload ? 'therapies' then
    if jsonb_typeof(p_payload -> 'therapies') <> 'array' or jsonb_array_length(p_payload -> 'therapies') > max_items then
      raise exception 'therapies must be a list' using errcode = '22023';
    end if;
    delete from public.profile_therapies where profile_id = p_profile_id;  -- rates go with them (cascade)
    for elem in select value from jsonb_array_elements(p_payload -> 'therapies') loop
      if jsonb_typeof(elem) <> 'object' then
        raise exception 'each therapy must be an object' using errcode = '22023';
      end if;
      tid := public.revision_int(elem -> 'therapy_id', 'therapy_id');
      if not exists (select 1 from public.therapies where id = tid and is_active) then
        raise exception 'unknown or inactive therapy' using errcode = '22023';
      end if;
      mins := case when jsonb_typeof(elem -> 'session_minutes') in ('number')
                   then public.revision_int(elem -> 'session_minutes', 'session_minutes') else null end;
      if elem ? 'session_minutes' and jsonb_typeof(elem -> 'session_minutes') not in ('number', 'null') then
        raise exception 'session_minutes must be a number or null' using errcode = '22023';
      end if;
      insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values (p_profile_id, tid, mins);
      -- service modes and session formats of THIS therapy: each list is required and has at least one item
      -- modalidades y formatos de sesión de ESTA terapia: cada lista es obligatoria y tiene al menos un elemento
      if jsonb_typeof(elem -> 'service_modes') is distinct from 'array' or jsonb_array_length(elem -> 'service_modes') not between 1 and 10 then
        raise exception 'each therapy needs a list of 1 to 10 service modes' using errcode = '22023';
      end if;
      for opt in select value from jsonb_array_elements(elem -> 'service_modes') loop
        v := public.revision_int(opt, 'service mode id');
        if not exists (select 1 from public.service_modes where id = v and is_active) then
          raise exception 'unknown or inactive service mode' using errcode = '22023';
        end if;
        insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
          values (p_profile_id, tid, v) on conflict do nothing;
      end loop;
      if jsonb_typeof(elem -> 'session_formats') is distinct from 'array' or jsonb_array_length(elem -> 'session_formats') not between 1 and 10 then
        raise exception 'each therapy needs a list of 1 to 10 session formats' using errcode = '22023';
      end if;
      for opt in select value from jsonb_array_elements(elem -> 'session_formats') loop
        v := public.revision_int(opt, 'session format id');
        if not exists (select 1 from public.session_formats where id = v and is_active) then
          raise exception 'unknown or inactive session format' using errcode = '22023';
        end if;
        insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id)
          values (p_profile_id, tid, v) on conflict do nothing;
      end loop;
      if elem ? 'rates' then
        if jsonb_typeof(elem -> 'rates') <> 'array' or jsonb_array_length(elem -> 'rates') > 10 then
          raise exception 'rates must be a list' using errcode = '22023';
        end if;
        for rate in select value from jsonb_array_elements(elem -> 'rates') loop
          if jsonb_typeof(rate) <> 'object' or jsonb_typeof(rate -> 'amount') <> 'number' then
            raise exception 'each rate needs rate_audience_id, amount and currency_id' using errcode = '22023';
          end if;
          if not exists (select 1 from public.rate_audiences
                         where id = public.revision_int(rate -> 'rate_audience_id', 'rate_audience_id') and is_active) then
            raise exception 'unknown or inactive rate audience' using errcode = '22023';
          end if;
          if not exists (select 1 from public.currencies
                         where id = public.revision_int(rate -> 'currency_id', 'currency_id') and is_active) then
            raise exception 'unknown or inactive currency' using errcode = '22023';
          end if;
          insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id)
            values (p_profile_id, tid, (rate ->> 'rate_audience_id')::smallint, (rate ->> 'amount')::numeric,
                    (rate ->> 'currency_id')::smallint);
        end loop;
      end if;
    end loop;
  end if;

  -- contacts: upsert the given ones, then remove the rest (a published profile cannot lose its phone)
  -- contactos: se guardan los dados y se quitan los demás (un perfil publicado no puede perder el teléfono)
  -- The payload carried the therapies WITH their rates: the admin approves those rates, so they count as confirmed now.
  -- El payload trajo las terapias CON sus tarifas: el admin aprueba esas tarifas, así que cuentan como confirmadas hoy.
  if p_payload ? 'therapies' then
    update public.therapist_profiles set rates_confirmed_at = now() where id = p_profile_id;
  end if;

  if p_payload ? 'contacts' then
    if jsonb_typeof(p_payload -> 'contacts') <> 'array' or jsonb_array_length(p_payload -> 'contacts') > 10 then
      raise exception 'contacts must be a list' using errcode = '22023';
    end if;
    types := '{}';
    for elem in select value from jsonb_array_elements(p_payload -> 'contacts') loop
      if jsonb_typeof(elem) <> 'object' or jsonb_typeof(elem -> 'value') <> 'string'
         or jsonb_typeof(coalesce(elem -> 'accepts_whatsapp', 'false'::jsonb)) <> 'boolean' then
        raise exception 'each contact needs contact_type_id, value and optionally accepts_whatsapp' using errcode = '22023';
      end if;
      v := public.revision_int(elem -> 'contact_type_id', 'contact_type_id');
      if not exists (select 1 from public.contact_types where id = v and is_active) then
        raise exception 'unknown or inactive contact type' using errcode = '22023';
      end if;
      types := types || v;
      insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
        values (p_profile_id, v, elem ->> 'value', coalesce((elem ->> 'accepts_whatsapp')::boolean, false))
        on conflict (profile_id, contact_type_id)
        do update set value = excluded.value, accepts_whatsapp = excluded.accepts_whatsapp;
    end loop;
    delete from public.profile_contacts where profile_id = p_profile_id and contact_type_id <> all (types);
  end if;
end
$$;

-- search_profiles: the filter and the grouping use the modes of the searched therapy.
-- search_profiles: el filtro y el agrupamiento usan las modalidades de la terapia buscada.
create or replace function public.search_profiles(
  p_therapy_id   integer,
  p_location_id  integer,
  p_service_mode text    default null,
  p_limit        integer default 20,
  p_offset       integer default 0)
returns table (
  result_group smallint, total_count bigint,
  profile_id uuid, display_name text, photo_path text, headline text, zone text, approved_at timestamptz,
  city_id integer, city_name text, region_id integer, region_name text, country_id integer, country_name text, country_iso text,
  therapy_ids integer[], therapy_names text[], service_modes text[], session_formats text[], languages text[], rates_from jsonb,
  rates_confirmed_at timestamptz, rates_current boolean, is_pinned boolean)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  loc_level   text;
  loc_country integer;
begin
  if p_therapy_id is null or p_location_id is null then
    raise exception 'therapy and location are required' using errcode = '22023';
  end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_offset is null or p_offset not between 0 and 10000 then
    raise exception 'offset must be between 0 and 10000' using errcode = '22023';
  end if;
  if not exists (select 1 from public.therapies t where t.id = p_therapy_id and t.is_active) then
    raise exception 'unknown therapy' using errcode = '22023';
  end if;
  if p_service_mode is not null and not exists (select 1 from public.service_modes m where m.code = p_service_mode and m.is_active) then
    raise exception 'unknown service mode' using errcode = '22023';
  end if;
  select ll.code into loc_level
    from public.locations l join public.location_levels ll on ll.id = l.level_id
    where l.id = p_location_id and l.is_active;
  if loc_level is null then
    raise exception 'unknown location' using errcode = '22023';
  end if;
  -- the country of the chosen place (itself, or the nearest ancestor that is a country)
  with recursive up as (
    select l.id, l.parent_id, l.level_id from public.locations l where l.id = p_location_id
    union all
    select l.id, l.parent_id, l.level_id from public.locations l join up on l.id = up.parent_id)
  select max(up.id) into loc_country from up join public.location_levels ll on ll.id = up.level_id where ll.code = 'country';

  return query
  with base as (
    -- the modes that count are those of the SEARCHED therapy (not of the whole profile)
    -- las modalidades que cuentan son las de la terapia BUSCADA (no las de todo el perfil)
    select c.*,
      coalesce((select array_agg(m.code) from public.profile_therapy_service_modes x
                join public.service_modes m on m.id = x.service_mode_id and m.is_active
                where x.profile_id = c.profile_id and x.therapy_id = p_therapy_id), '{}') as therapy_modes
    from public.public_profile_cards c
    where c.therapy_ids @> array[p_therapy_id]
  ), filtered as (
    select b.* from base b
    where p_service_mode is null or p_service_mode = any (b.therapy_modes)
  ), grouped as (
    select b.*,
      case
        when p_location_id in (b.city_id, b.region_id, b.country_id) then 1  -- a country search ends here for every profile of that country
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.therapy_modes)
             and b.country_id = loc_country then 2
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.therapy_modes) then 3
      end as g
    from filtered b
  )
  select g.g::smallint, count(*) over (),
         g.profile_id, g.display_name, g.photo_path, g.headline, g.zone, g.approved_at,
         g.city_id, g.city_name, g.region_id, g.region_name, g.country_id, g.country_name, g.country_iso,
         g.therapy_ids, g.therapy_names, g.service_modes, g.session_formats, g.languages, g.rates_from,
         g.rates_confirmed_at, g.rates_current, g.is_pinned
  from grouped g
  where g.g is not null
  -- Order inside a group (owner decision 12/11/2026): the site-owner pin, then current prices, then a photo, then the
  -- oldest approval. Orden dentro del grupo (decisión del titular, 12/11/2026): el perfil fijado del sitio, luego precios
  -- al día, luego foto, luego la aprobación más antigua.
  order by g.g, g.is_pinned desc, g.rates_current desc, (g.photo_path is not null) desc, g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;

-- ============================================================================
-- 7. The old profile-level tables are gone / Las tablas viejas del perfil se eliminan
-- ============================================================================
drop table public.profile_service_modes;
drop table public.profile_session_formats;
