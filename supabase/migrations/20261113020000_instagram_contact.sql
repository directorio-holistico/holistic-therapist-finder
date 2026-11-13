-- Instagram as an optional PUBLIC contact. SECURITY CHANGE: it changes a view that anonymous visitors can read.
-- Instagram como contacto PÚBLICO opcional. CAMBIO DE SEGURIDAD: cambia una vista que pueden leer los visitantes anónimos.
--
-- Owner request (13/11/2026) / Pedido del titular (13/11/2026): therapists can add their Instagram.
--  * New row in the contact_types catalog (public like the website: is_private = false). The phone and the email stay private.
--    Fila nueva en el catálogo contact_types (pública como la web: is_private = false). El teléfono y el mail siguen privados.
--  * The value is the user name only (the form turns "@user" or a profile link into "user"); the guard enforces the format.
--    El valor es solo el usuario (el formulario convierte "@usuario" o un enlace en "usuario"); la guarda exige el formato.
--  * public_profile_detail gets ONE new column at the end (instagram), read through public_contact_code like the website, so it
--    only shows the value when the type is active and public. Grants do not change. public_profile_cards does not change.
--    public_profile_detail suma UNA columna al final (instagram), leída con public_contact_code como la web, por eso solo
--    muestra el valor si el tipo está activo y es público. Los permisos no cambian. public_profile_cards no cambia.
--  * apply_revision_payload needs no change: it takes any contact type of the catalog and the table guard validates the value.
--    apply_revision_payload no cambia: acepta cualquier tipo del catálogo y la guarda de la tabla valida el valor.

insert into public.contact_types (code, is_required, is_private, sort_order)
  values ('instagram', false, false, 4)
  on conflict (code) do nothing;

create or replace function public.profile_contacts_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  type_code text;
  profile_status text;
begin
  if tg_op = 'DELETE' then
    select ct.code into type_code from public.contact_types ct where ct.id = old.contact_type_id;
    select ps.code into profile_status
      from public.therapist_profiles tp join public.profile_statuses ps on ps.id = tp.status_id
      where tp.id = old.profile_id;
    -- profile_status is null while the profile itself is being deleted (cascade): that is allowed
    -- profile_status es nulo mientras se borra el perfil entero (cascada): eso se permite
    if type_code = 'phone' and profile_status = 'published' then
      raise exception 'a published profile cannot lose its phone' using errcode = '23514';
    end if;
    return old;
  end if;

  select code into strict type_code from public.contact_types where id = new.contact_type_id;
  if new.accepts_whatsapp and type_code <> 'phone' then
    raise exception 'accepts_whatsapp only applies to the phone' using errcode = '23514';
  end if;
  if type_code = 'phone' then
    if new.value !~ '^\+?[0-9 ()-]+$' or length(regexp_replace(new.value, '[^0-9]', '', 'g')) not between 6 and 15 then
      raise exception 'invalid phone' using errcode = '23514';
    end if;
  elsif type_code = 'email' then
    if new.value <> lower(new.value) or new.value !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' then
      raise exception 'invalid email (lower case, name@domain.tld)' using errcode = '23514';
    end if;
  elsif type_code = 'instagram' then
    -- the handle only: no @, no link, lower case (letters, digits, dot, underscore; up to 30)
    -- solo el usuario: sin @, sin enlace, en minúsculas (letras, números, punto, guion bajo; hasta 30)
    if new.value !~ '^[a-z0-9._]{1,30}$' then
      raise exception 'invalid instagram (the user name only: lower case letters, digits, dot and underscore, up to 30)' using errcode = '23514';
    end if;
  elsif type_code = 'website' then
    if new.value !~ '^https?://[^ ]+$' then
      raise exception 'invalid website (must start with http:// or https://)' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

-- The detail view keeps its name, its columns and its grants; only "instagram" is added at the end.
-- La vista de detalle conserva nombre, columnas y permisos; solo se suma "instagram" al final.
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
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'instagram') as instagram
from public.public_profile_cards c
join public.therapist_profiles tp on tp.id = c.profile_id;
comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';
