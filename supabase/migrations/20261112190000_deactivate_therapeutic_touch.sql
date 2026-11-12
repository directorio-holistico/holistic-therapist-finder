-- Hides "Toque Terapéutico" from visitors. Owner decision 12/11/2026: the catalog is refined as therapists join.
-- Not a security change: one catalog row is deactivated (no table, grant or policy changes). Reversible:
--   update public.therapies set is_active = true where code = 'therapeutic_touch';
-- Oculta "Toque Terapéutico" para los visitantes. Decisión del titular (12/11/2026): el catálogo se va depurando a medida
-- que se suman terapeutas. No es un cambio de seguridad: se desactiva una fila de catálogo. Reversible con la línea de arriba.

do $$
declare
  changed integer;
begin
  update public.therapies set is_active = false where code = 'therapeutic_touch' and is_active;
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'expected to deactivate exactly 1 therapy (therapeutic_touch), got %', changed;
  end if;
end
$$;
