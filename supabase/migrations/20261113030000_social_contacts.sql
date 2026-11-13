-- Facebook, TikTok and YouTube as optional PUBLIC contacts. SECURITY CHANGE: it changes a view that anonymous visitors can read.
-- Facebook, TikTok y YouTube como contactos PÚBLICOS opcionales. CAMBIO DE SEGURIDAD: cambia una vista que pueden leer los visitantes anónimos.
--
-- Owner request (13/11/2026) / Pedido del titular (13/11/2026): all optional, like the Instagram.
--  * Three new rows in contact_types (public: is_private = false). Phone and email stay private.
--    Tres filas nuevas en contact_types (públicas: is_private = false). Teléfono y mail siguen privados.
--  * The value is the profile LINK. The guard accepts only https links to those sites and only profile or channel pages, so a public
--    value can never point to another site (look-alike hosts such as facebook.com.evil.test or user-info tricks do not match).
--    El valor es el ENLACE del perfil. La guarda acepta solo enlaces https a esos sitios y solo páginas de perfil o canal, así un
--    valor público nunca puede apuntar a otro sitio (hosts parecidos como facebook.com.evil.test o trucos con usuario no coinciden).
--  * public_profile_detail gets THREE new columns at the end (facebook, tiktok, youtube), read through public_contact_code like the
--    website and the instagram. Grants do not change. public_profile_cards does not change.
--    public_profile_detail suma TRES columnas al final (facebook, tiktok, youtube), leídas con public_contact_code como la web y el
--    instagram. Los permisos no cambian. public_profile_cards no cambia.

insert into public.contact_types (code, is_required, is_private, sort_order) values
  ('facebook', false, false, 5), ('tiktok', false, false, 6), ('youtube', false, false, 7)
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
  elsif type_code = 'facebook' then
    -- https link on facebook.com / fb.com (optionally www. or m.), with a path; nothing else
    -- enlace https a facebook.com / fb.com (con www. o m. opcional), con una ruta; nada más
    if new.value !~ '^https://(www\.|m\.)?(facebook\.com|fb\.com)/[^ ]+$' then
      raise exception 'invalid facebook (https link to facebook.com)' using errcode = '23514';
    end if;
  elsif type_code = 'tiktok' then
    -- profile link only: tiktok.com/@user (2 to 24 letters, digits, dot, underscore)
    -- solo enlace de perfil: tiktok.com/@usuario (2 a 24 letras, números, punto, guion bajo)
    if new.value !~ '^https://(www\.)?tiktok\.com/@[A-Za-z0-9._]{2,24}/?$' then
      raise exception 'invalid tiktok (profile link: https://www.tiktok.com/@user)' using errcode = '23514';
    end if;
  elsif type_code = 'youtube' then
    -- channel link only: /@handle, /channel/UC…, /c/name or /user/name (no videos, no short links)
    -- solo enlace de canal: /@canal, /channel/UC…, /c/nombre o /user/nombre (sin videos ni enlaces cortos)
    if new.value !~ '^https://(www\.|m\.)?youtube\.com/(@[A-Za-z0-9._-]{3,30}|channel/UC[A-Za-z0-9_-]{22}|c/[A-Za-z0-9._-]+|user/[A-Za-z0-9._-]+)/?$' then
      raise exception 'invalid youtube (channel link: https://www.youtube.com/@channel)' using errcode = '23514';
    end if;
  elsif type_code = 'website' then
    if new.value !~ '^https?://[^ ]+$' then
      raise exception 'invalid website (must start with http:// or https://)' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

-- The detail view keeps its name, columns and grants; only the three columns are added at the end.
-- La vista de detalle conserva nombre, columnas y permisos; solo se suman las tres columnas al final.
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
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'instagram') as instagram,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'facebook') as facebook,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'tiktok') as tiktok,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'youtube') as youtube
from public.public_profile_cards c
join public.therapist_profiles tp on tp.id = c.profile_id;
comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';
