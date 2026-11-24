-- SECURITY CHANGE / CAMBIO DE SEGURIDAD: 1 new function (admin only). No table, grant, policy or trigger changes.
-- Nueva: 1 función (solo admin). No cambia tablas, permisos, políticas ni triggers.
--
-- A therapist can ask for a therapy that is not in the list; the name stays in profile_revisions.suggested_therapy. Once the administrator
-- has decided the revision and evaluated the request, this function clears that text, so a person's request does not stay stored forever
-- (data minimisation). It keeps the trace: who cleared which revision goes to the audit log (column NAME only, never the text).
-- Un terapeuta puede pedir una terapia que no está en la lista; el nombre queda en profile_revisions.suggested_therapy. Cuando el
-- administrador ya decidió la revisión y evaluó el pedido, esta función borra ese texto, para que el pedido de una persona no quede
-- guardado para siempre (minimización de datos). Deja el rastro: quién limpió qué revisión va a la auditoría (solo el NOMBRE de la columna).
--
--  * Only a DECIDED revision (approved, rejected or discarded): an open one belongs to the therapist or still awaits the decision.
--    Solo una revisión DECIDIDA (aprobada, rechazada o descartada): una abierta es del terapeuta o espera la decisión.
--  * Errors: 42501 not an administrator; P0002 the revision does not exist or has no request; 55000 the revision is still open.
--    Errores: 42501 no es admin; P0002 la revisión no existe o no tiene pedido; 55000 la revisión sigue abierta.


create function public.admin_dismiss_suggested_therapy(p_revision_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person uuid := public.current_person_id();
  rev    public.profile_revisions%rowtype;
begin
  if person is null or not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_revision_id is null then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  select * into rev from public.profile_revisions where id = p_revision_id for update;
  if not found or rev.suggested_therapy is null then
    raise exception 'nothing to dismiss' using errcode = 'P0002';
  end if;
  if rev.closed_at is null then
    raise exception 'the revision is still open' using errcode = '55000';
  end if;

  update public.profile_revisions set suggested_therapy = null where id = p_revision_id;
  insert into public.audit_log (table_name, operation, row_key, changed_fields, actor_person_id, actor_role)
  values ('profile_revisions', 'UPDATE', p_revision_id::text, array['suggested_therapy'], person, 'authenticated');
end
$$;
revoke execute on function public.admin_dismiss_suggested_therapy(uuid) from public, anon, service_role;
grant execute on function public.admin_dismiss_suggested_therapy(uuid) to authenticated;

