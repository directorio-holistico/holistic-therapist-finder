-- DEMO profiles: 6 FICTITIOUS therapists (2 per country: AR, MX, ES). Everything is invented.
-- Perfiles DEMO: 6 terapeutas FICTICIOS (2 por país: AR, MX, ES). Todo es inventado.
--
--  * Marker / Marca: email on the reserved domain demo.invalid (RFC 2606, it can never receive mail) AND full_name and
--    display_name starting with "[DEMO] ". The card shows the name, so it says DEMO. remove-demo.sql deletes by that marker.
--    Mail en el dominio reservado demo.invalid (RFC 2606, nunca puede recibir correo) Y nombre que empieza con "[DEMO] ".
--    La tarjeta muestra el nombre, así que dice DEMO. remove-demo.sql borra por esa marca.
--  * All offer LNT + ONE different second therapy. Prices: 2 current, 2 expired (8 months), 2 without prices.
--    Todos ofrecen LNT + UNA segunda terapia distinta. Tarifas: 2 al día, 2 vencidas (8 meses), 2 sin tarifas.
--  * Phones are obviously fake. No real person, no real contact. / Teléfonos obviamente falsos. Nada real.
--  * NOT a migration: it is run by hand (Demo-Remote.ps1 -Action Load) and removed before opening to the public.
--    NO es una migración: se corre a mano (Demo-Remote.ps1 -Action Load) y se quita antes de abrir al público.
--  * Runs as the database owner (not as anon/authenticated), in ONE transaction: all or nothing.
--    Corre como dueño de la base (no como anon/authenticated), en UNA transacción: todo o nada.

do $$
declare
  es        smallint := (select id from public.languages where code = 'es');
  lnt       integer  := (select id from public.therapies where code = 'lnt_schwiderski' and is_active);
  st_unpub  smallint := (select id from public.profile_statuses where code = 'unpublished');
  st_pub    smallint := (select id from public.profile_statuses where code = 'published');
  role_th   smallint := (select id from public.roles where code = 'therapist');
  ct_phone  smallint := (select id from public.contact_types where code = 'phone');
  ct_email  smallint := (select id from public.contact_types where code = 'email');
  aud_own   smallint := (select id from public.rate_audiences where code = 'own_country');
  aud_other smallint := (select id from public.rate_audiences where code = 'other_countries');
  usd       smallint := (select id from public.currencies where code = 'USD');
  d         record;
  person    uuid;
  prof      uuid;
  city      integer;
  second    integer;
  cur       smallint;
  n         integer := 0;
begin
  if lnt is null or es is null then raise exception 'LNT therapy or Spanish language missing'; end if;
  if exists (select 1 from public.people where email like '%@demo.invalid') then
    raise exception 'DEMO data already loaded: run remove-demo.sql first / ya hay datos DEMO: corré remove-demo.sql primero';
  end if;

  for d in select * from (values
    -- key, name, country, region, city, second therapy, currency, prices, languages, in_person, remote, group, whatsapp, headline
    ('ar1', 'Lucía Ferrante',    'AR', 'Río Negro',            'Cinco Saltos', 'reiki',                  'ARS', 'current', 'es',    true,  true,  false, true,  'Sesiones de LNT y Reiki en un espacio tranquilo.'),
    ('ar2', 'Mateo Quiroga',     'AR', 'Santa Fe',             'Rosario',      'family_constellations',  'ARS', 'expired', 'es,en', false, true,  true,  false, 'LNT y Constelaciones Familiares, individual y en grupo.'),
    ('mx1', 'Ximena Barrientos', 'MX', 'Jalisco',              'Guadalajara',  'biodecoding',            'MXN', 'none',    'es',    true,  false, false, true,  'Acompañamiento con LNT y BioDecodificación.'),
    ('mx2', 'Iván Castellanos',  'MX', 'Yucatán',              'Mérida',       'akashic_records',        'MXN', 'current', 'es,pt', true,  true,  true,  true,  'LNT y Registros Akáshicos, presencial y a distancia.'),
    ('es1', 'Marina Solsona',    'ES', 'Cataluña',             'Barcelona',    'meditation_mindfulness', 'EUR', 'expired', 'es,en', true,  true,  true,  false, 'LNT y Meditación guiada para el día a día.'),
    ('es2', 'Álvaro Montesinos', 'ES', 'Comunidad de Madrid',  'Madrid',       'quantum_therapy',        'EUR', 'none',    'es',    false, true,  false, false, 'Sesiones a distancia de LNT y Terapia Cuántica.')
  ) as v(k, name, iso, region, city, second, cur, prices, langs, in_person, remote, grp, wa, headline)
  loop
    select l.id into city
      from public.locations l
      join public.location_translations lt on lt.location_id = l.id and lt.language_id = es and lt.name = d.city
      join public.locations r on r.id = l.parent_id
      join public.location_translations rt on rt.location_id = r.id and rt.language_id = es and rt.name = d.region
      join public.locations p on p.id = r.parent_id and p.iso_code = d.iso
      where l.level_id = (select id from public.location_levels where code = 'city');
    if city is null then raise exception 'city not found (load the starter cities first): %', d.city; end if;
    select id into second from public.therapies where code = d.second and is_active;
    if second is null then raise exception 'second therapy missing or inactive: %', d.second; end if;
    cur := (select id from public.currencies where code = d.cur);

    insert into public.people (full_name, email)
      values ('[DEMO] ' || d.name, 'demo.' || d.k || '@demo.invalid') returning id into person;
    insert into public.person_roles (person_id, role_id) values (person, role_th);

    insert into public.therapist_profiles (person_id, status_id, location_id, display_name, headline, approved_at, rates_confirmed_at)
      values (person, st_unpub, city, '[DEMO] ' || d.name, 'Perfil ficticio de demostración. ' || d.headline,
              now() - make_interval(days => 3 + n),
              case d.prices when 'current' then now() - interval '10 days'
                            when 'expired' then now() - interval '8 months' end)
      returning id into prof;

    insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values (prof, lnt, 60), (prof, second, 45);
    insert into public.profile_languages (profile_id, language_id)
      select prof, g.id from public.languages g where g.code = any (string_to_array(d.langs, ','));
    insert into public.profile_service_modes (profile_id, service_mode_id)
      select prof, m.id from public.service_modes m
      where (m.code = 'in_person' and d.in_person) or (m.code = 'remote' and d.remote);
    insert into public.profile_session_formats (profile_id, session_format_id)
      select prof, f.id from public.session_formats f where f.code = 'individual' or (f.code = 'group' and d.grp);

    if d.prices <> 'none' then
      insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id) values
        (prof, lnt,    aud_own,   case d.cur when 'ARS' then 25000 when 'MXN' then 600 else 45 end, cur),
        (prof, second, aud_own,   case d.cur when 'ARS' then 20000 when 'MXN' then 500 else 35 end, cur),
        (prof, lnt,    aud_other, 40, usd);
    end if;

    -- fake contacts; the phone must exist BEFORE publishing / contactos falsos; el teléfono debe existir ANTES de publicar
    insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
      values (prof, ct_phone, '+00 0000 00000' || (n + 1), d.wa),
             (prof, ct_email, 'demo.' || d.k || '@demo.invalid', false);
    update public.therapist_profiles set status_id = st_pub where id = prof;
    n := n + 1;
  end loop;
  raise notice 'DEMO loaded: % profiles / DEMO cargado: % perfiles', n, n;
end
$$;
