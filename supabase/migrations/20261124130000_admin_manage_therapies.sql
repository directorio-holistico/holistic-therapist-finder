-- SECURITY CHANGE / CAMBIO DE SEGURIDAD: 2 new functions (admin only) + 2 audit triggers. No table, grant or policy changes.
-- Nuevas: 2 funciones (solo admin) + 2 triggers de auditoría. No cambia tablas, permisos ni políticas.
--
-- The therapy catalog is read-only for the API (anon and authenticated only SELECT). Until now the owner changed it by hand
-- in the SQL Editor. These two functions let an ADMINISTRATOR add a therapy and hide / show one from the admin screen, without
-- opening any table to writing.
-- El catálogo de terapias es de solo lectura para la API (anon y authenticated solo hacen SELECT). Hasta ahora el dueño lo
-- cambiaba a mano en el SQL Editor. Estas dos funciones dejan que un ADMINISTRADOR agregue una terapia y la oculte / muestre desde
-- la pantalla de administración, sin abrir ninguna tabla a la escritura.
--
--  * "Who added it": the audit log already records the actor (actor_person_id). Instead of a new column on `therapies` (which
--    visitors can read), the two catalog tables get an audit trigger: who / what / when, with column NAMES only, no personal value.
--    "Quién la agregó": la auditoría ya registra al actor (actor_person_id). En vez de una columna nueva en `therapies` (que los
--    visitantes pueden leer), las dos tablas del catálogo reciben un trigger de auditoría: quién / qué / cuándo, solo con NOMBRES
--    de columnas, sin ningún valor personal.
--  * Deactivating never deletes: profiles keep the therapy, visitors stop seeing it, and a revision that picks it cannot be
--    approved until it is shown again (same behaviour as the therapies already hidden).
--    Desactivar nunca borra: los perfiles conservan la terapia, los visitantes dejan de verla, y una revisión que la elige no se
--    puede aprobar hasta mostrarla de nuevo (igual que las terapias ya ocultas).
--  * Only Spanish names for now (Phase 1). / Solo nombres en español por ahora (Fase 1).


-- 1) Audit of the catalog / Auditoría del catálogo
create trigger audit_therapies
  after insert or update or delete on public.therapies
  for each row execute function public.audit_row_change('id');
create trigger audit_therapy_translations
  after insert or update or delete on public.therapy_translations
  for each row execute function public.audit_row_change('therapy_id', 'language_id');

-- 2) admin_add_therapy: returns the id of the new therapy. Duplicated code or name -> 23505 (existing unique indexes).
-- 2) admin_add_therapy: devuelve el id de la terapia nueva. Código o nombre repetido -> 23505 (índices únicos existentes).
create function public.admin_add_therapy(
  p_code       text,
  p_name       text,
  p_short_name text     default null,
  p_sort_order smallint default null,
  p_is_active  boolean  default true
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person uuid     := public.current_person_id();
  es     smallint := (select id from public.languages where code = 'es');
  new_id integer;
  v_sort smallint;
begin
  if person is null or not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,59}$' then
    raise exception 'invalid code' using errcode = '22023';
  end if;
  if p_name is null or p_name <> btrim(p_name) or char_length(p_name) not between 1 and 120 then
    raise exception 'invalid name' using errcode = '22023';
  end if;
  if p_short_name is not null and (p_short_name <> btrim(p_short_name) or char_length(p_short_name) not between 1 and 40) then
    raise exception 'invalid short name' using errcode = '22023';
  end if;
  if p_sort_order is not null and p_sort_order not between 1 and 30000 then
    raise exception 'invalid sort order' using errcode = '22023';
  end if;
  v_sort := coalesce(p_sort_order, ((select coalesce(max(sort_order), 0) + 10 from public.therapies))::smallint);

  insert into public.therapies (code, sort_order, is_active)
  values (p_code, v_sort, coalesce(p_is_active, true))
  returning id into new_id;
  insert into public.therapy_translations (therapy_id, language_id, name, short_name)
  values (new_id, es, p_name, p_short_name);
  return new_id;
end
$$;
revoke execute on function public.admin_add_therapy(text, text, text, smallint, boolean) from public, anon, service_role;
grant execute on function public.admin_add_therapy(text, text, text, smallint, boolean) to authenticated;

-- 3) admin_set_therapy_active: hide or show an existing therapy. Unknown id -> P0002.
-- 3) admin_set_therapy_active: oculta o muestra una terapia existente. Id inexistente -> P0002.
create function public.admin_set_therapy_active(p_therapy_id integer, p_is_active boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person uuid := public.current_person_id();
begin
  if person is null or not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_therapy_id is null or p_is_active is null then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  update public.therapies set is_active = p_is_active where id = p_therapy_id;
  if not found then
    raise exception 'therapy not found' using errcode = 'P0002';
  end if;
end
$$;
revoke execute on function public.admin_set_therapy_active(integer, boolean) from public, anon, service_role;
grant execute on function public.admin_set_therapy_active(integer, boolean) to authenticated;

