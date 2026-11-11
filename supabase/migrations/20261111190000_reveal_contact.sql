-- Contact reveal. SECURITY CHANGE: 1 table, 2 functions (1 callable by visitors), 1 setting.
-- Revelado de contacto. CAMBIO DE SEGURIDAD: 1 tabla, 2 funciones (1 invocable por visitantes), 1 ajuste.
--
--  * Phone and email (the contact types marked is_private) leave the database ONLY through reveal_contact(profile_id),
--    for a published profile. No view, no policy, no column grant reaches them (commits 12 and 19).
--    El teléfono y el mail (tipos de contacto con is_private) salen de la base SOLO por reveal_contact(perfil), de un perfil
--    publicado. Ninguna vista, política ni permiso de columna los alcanza (commits 12 y 19).
--  * A profile that is not published (or does not exist) returns no rows and records nothing: the answer does not tell
--    "it exists but is hidden" from "it does not exist". / Un perfil no publicado (o inexistente) devuelve cero filas y no
--    registra nada: la respuesta no distingue "existe pero está oculto" de "no existe".
--  * Each call that returns contacts adds 1 to a daily counter per profile (no IP, no visitor identifier). Only the admin
--    reads it. Cascade: when a profile is deleted (erasure) its counters go with it.
--    Cada llamada que devuelve contactos suma 1 a un contador diario por perfil (sin IP ni identificador). Solo lo lee el
--    admin. En cascada: al borrar un perfil (derecho al olvido) se van sus contadores.
--  * NOT here yet: rate limiting by origin (needs an ADR) / TODAVÍA NO: límite de pedidos por origen (necesita un ADR).

alter table public.app_settings drop constraint app_settings_value_valid;
alter table public.app_settings add constraint app_settings_value_valid check (
  case key
    when 'max_therapies_per_profile'
      then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
    when 'review_days_initial' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_update' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_priority' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'moderation_allow_self_approval' then jsonb_typeof(value) = 'boolean'
    when 'retention_unmet_searches_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_contact_reveals_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('retention_contact_reveals_months', '12', false,
   'Months to keep the contact-reveal counters (1-120) / Meses que se conservan los contadores de revelado de contacto (1-120)');

create table public.contact_reveals (
  id             bigint generated always as identity primary key,
  profile_id     uuid    not null references public.therapist_profiles (id) on delete cascade,
  day            date    not null,
  reveals_count  integer not null default 1 check (reveals_count between 1 and 1000000),
  unique (profile_id, day)
);
create index contact_reveals_day_idx on public.contact_reveals (day);
comment on table public.contact_reveals is
  'Contact reveals per profile and UTC day. No IP, no visitor data / Revelados de contacto por perfil y día UTC. Sin IP ni datos del visitante.';

-- SECURITY: RLS + GRANT. Only the admin reads; nobody writes through the API.
alter table public.contact_reveals enable row level security;
grant select on public.contact_reveals to authenticated;
create policy contact_reveals_select_admin on public.contact_reveals
  for select to authenticated using ((select public.is_admin()));

create function public.reveal_contact(p_profile_id uuid)
returns table (contact_type text, value text, accepts_whatsapp boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
begin
  if p_profile_id is null or not public.is_published_profile(p_profile_id) then
    return;
  end if;
  if not exists (select 1 from public.profile_contacts pc join public.contact_types ct on ct.id = pc.contact_type_id
                  where pc.profile_id = p_profile_id and ct.is_active and ct.is_private) then
    return;
  end if;
  insert into public.contact_reveals as r (profile_id, day) values (p_profile_id, today)
    on conflict (profile_id, day) do update set reveals_count = least(r.reveals_count + 1, 1000000);
  return query
    select ct.code::text, pc.value, pc.accepts_whatsapp
      from public.profile_contacts pc join public.contact_types ct on ct.id = pc.contact_type_id
     where pc.profile_id = p_profile_id and ct.is_active and ct.is_private
     order by ct.code;
end
$$;
revoke execute on function public.reveal_contact(uuid) from public, authenticated, service_role;
grant execute on function public.reveal_contact(uuid) to anon;

create function public.purge_expired_contact_reveals()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  months  integer;
  removed integer;
begin
  select (value::text)::int into months from public.app_settings where key = 'retention_contact_reveals_months';
  if months is null then
    raise exception 'setting retention_contact_reveals_months is missing' using errcode = '23514';
  end if;
  delete from public.contact_reveals
    where day < ((now() at time zone 'utc')::date - make_interval(months => months))::date;
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.purge_expired_contact_reveals() from public, anon, authenticated;
grant execute on function public.purge_expired_contact_reveals() to service_role;
