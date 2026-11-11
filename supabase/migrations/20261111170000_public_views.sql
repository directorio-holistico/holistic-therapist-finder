-- Public views: the ONLY thing a visitor (anon) can read about therapists. SECURITY CHANGE: 2 views, 2 helper functions,
-- anon read access (column by column) on 7 profile tables, 7 row policies.
-- Vistas públicas: LO ÚNICO que un visitante (anon) puede leer sobre los terapeutas. CAMBIO DE SEGURIDAD.
--
-- THE WRITTEN LIST of what anon can read (besides the 10 public catalogs of commit 8) / LA LISTA ESCRITA de lo que lee anon:
--   therapist_profiles   : id, location_id, display_name, zone, headline, practice_start_year, photo_path, approved_at
--                          (NOT person_id, status_id, status_reason, created_at)   rows: published profiles only
--   profile_therapies    : profile_id, therapy_id, session_minutes                  rows: of published profiles
--   profile_languages / profile_service_modes / profile_session_formats            rows: of published profiles
--   profile_therapy_rates: profile_id, therapy_id, rate_audience_id, amount, currency_id   rows: of published profiles
--   profile_contacts     : profile_id, contact_type_id, value                       rows: of published profiles AND of a
--                          non-private contact type (the website). Phone and email NEVER reach anon.
--   public_profile_cards, public_profile_detail (views, security_invoker)
-- Nothing in people, person_roles, revisions, acceptances, moderation, settings or restricted terms.
-- Nada de people, person_roles, revisiones, aceptaciones, moderación, ajustes ni términos restringidos.
--
-- Design / Diseño:
--  * Views use security_invoker = true: they run with the visitor's own permissions, so the grants and policies above
--    are what really limits them (a view cannot see more than its caller).
--    Las vistas usan security_invoker = true: corren con los permisos del visitante.
--  * Public pages are rendered with the anonymous role (static pages cannot depend on who is logged in), so these
--    policies are for anon only. A logged-in user querying the views sees only their own published profile (admin: all).
--    Las páginas públicas se generan con el rol anónimo; estas políticas son solo para anon.
--  * Two tiny read-only helper functions let the policies ask "is this profile published?" and "is this contact type
--    public?" without giving anon access to the internal catalogs (profile_statuses, contact_types).
--    Dos funciones auxiliares de solo lectura evitan darle a anon los catálogos internos.
--  * Phone and email are in no view; they will come out only through reveal_contact.
--    Teléfono y mail no están en ninguna vista; saldrán solo por reveal_contact.

-- ============================================================================
-- 1. Helper functions / Funciones auxiliares
-- ============================================================================
create function public.is_published_profile(p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.therapist_profiles tp
    join public.profile_statuses ps on ps.id = tp.status_id
    where tp.id = p_profile and ps.code = 'published')
$$;
revoke execute on function public.is_published_profile(uuid) from public, service_role;
grant execute on function public.is_published_profile(uuid) to anon, authenticated;

-- Returns the code of a contact type only when it is public (not private) and active; null otherwise.
-- Devuelve el código de un tipo de contacto solo si es público (no privado) y activo; si no, null.
create function public.public_contact_code(p_type smallint)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select ct.code from public.contact_types ct where ct.id = p_type and ct.is_active and not ct.is_private
$$;
revoke execute on function public.public_contact_code(smallint) from public, service_role;
grant execute on function public.public_contact_code(smallint) to anon, authenticated;

-- ============================================================================
-- 2. anon access to the base tables: column by column + published rows only
-- ============================================================================
grant select (id, location_id, display_name, zone, headline, practice_start_year, photo_path, approved_at)
  on public.therapist_profiles to anon;
grant select (profile_id, therapy_id, session_minutes) on public.profile_therapies to anon;
grant select (profile_id, language_id) on public.profile_languages to anon;
grant select (profile_id, service_mode_id) on public.profile_service_modes to anon;
grant select (profile_id, session_format_id) on public.profile_session_formats to anon;
grant select (profile_id, therapy_id, rate_audience_id, amount, currency_id) on public.profile_therapy_rates to anon;
grant select (profile_id, contact_type_id, value) on public.profile_contacts to anon;

create policy therapist_profiles_select_public on public.therapist_profiles
  for select to anon using (public.is_published_profile(id));
create policy profile_therapies_select_public on public.profile_therapies
  for select to anon using (public.is_published_profile(profile_id));
create policy profile_languages_select_public on public.profile_languages
  for select to anon using (public.is_published_profile(profile_id));
create policy profile_service_modes_select_public on public.profile_service_modes
  for select to anon using (public.is_published_profile(profile_id));
create policy profile_session_formats_select_public on public.profile_session_formats
  for select to anon using (public.is_published_profile(profile_id));
create policy profile_therapy_rates_select_public on public.profile_therapy_rates
  for select to anon using (public.is_published_profile(profile_id));
create policy profile_contacts_select_public on public.profile_contacts
  for select to anon using (public.is_published_profile(profile_id) and public.public_contact_code(contact_type_id) is not null);

-- ============================================================================
-- 3. The views / Las vistas (names in Spanish, the only language of the interface for now)
-- ============================================================================
create view public.public_profile_cards with (security_invoker = true) as
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
  coalesce(rt.rates_from, '{}'::jsonb) as rates_from
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
  select array_agg(m.code order by m.sort_order, m.id) as codes
  from public.profile_service_modes x join public.service_modes m on m.id = x.service_mode_id and m.is_active
  where x.profile_id = tp.id
) sm on true
left join lateral (
  select array_agg(f.code order by f.sort_order, f.id) as codes
  from public.profile_session_formats x join public.session_formats f on f.id = x.session_format_id and f.is_active
  where x.profile_id = tp.id
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

create view public.public_profile_detail with (security_invoker = true) as
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
    where pt.profile_id = c.profile_id), '[]'::jsonb) as therapies_detail
from public.public_profile_cards c
join public.therapist_profiles tp on tp.id = c.profile_id;

comment on view public.public_profile_cards is 'Search result card of a published profile; no phone, no email / Tarjeta de resultado de un perfil publicado; sin teléfono ni mail.';
comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';

-- Only these two views are readable by visitors / Solo estas dos vistas las lee el visitante
grant select on public.public_profile_cards, public.public_profile_detail to anon, authenticated;
