-- Checks for the REAL project after applying 20261118120000 / Controles del proyecto REAL tras aplicar 20261118120000.
-- Re-acceptance gate. SECURITY CHANGE: 1 column, 2 callable functions, 2 internal functions, 2 triggers, 4 functions replaced.
-- Puerta de re-aceptación. CAMBIO DE SEGURIDAD: 1 columna, 2 funciones invocables, 2 internas, 2 triggers, 4 funciones reemplazadas.
-- Parts 1-6 only read. Part 7 CHANGES DATA: run it ONLY when the app with the banner is deployed.
-- Las partes 1-6 solo leen. La parte 7 CAMBIA DATOS: correrla SOLO con la app del aviso ya desplegada.

-- 1) The column exists and the gate starts OFF. Expected / Esperado: 5 rows, minimum_version null in all
select code, is_required, minimum_version from public.legal_document_types order by sort_order;

-- 2) Security definer with a fixed search_path. Expected / Esperado: 3 rows, true | {search_path=pg_catalog, public}
select p.proname, p.prosecdef as security_definer, p.proconfig
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('my_pending_documents', 'assert_current_acceptances', 'accept_current_documents')
 order by p.proname;

-- 3) Who can execute what. Expected / Esperado:
--    my_pending_documents, accept_current_documents: anon false | authenticated true | service_role false
--    assert_current_acceptances, require_current_acceptances: false | false | false
select f.name,
       has_function_privilege('anon', f.sig, 'execute') as anon,
       has_function_privilege('authenticated', f.sig, 'execute') as authenticated,
       has_function_privilege('service_role', f.sig, 'execute') as service_role
  from (values ('my_pending_documents', 'public.my_pending_documents()'),
               ('accept_current_documents', 'public.accept_current_documents(jsonb)'),
               ('assert_current_acceptances', 'public.assert_current_acceptances()'),
               ('require_current_acceptances', 'public.require_current_acceptances()')) as f(name, sig);

-- 4) The four replaced functions keep their permissions. Expected / Esperado: anon false | authenticated true | service_role false
select f.name,
       has_function_privilege('anon', f.sig, 'execute') as anon,
       has_function_privilege('authenticated', f.sig, 'execute') as authenticated,
       has_function_privilege('service_role', f.sig, 'execute') as service_role
  from (values ('submit_revision', 'public.submit_revision(uuid)'),
               ('update_my_rates', 'public.update_my_rates(jsonb)'),
               ('confirm_my_rates', 'public.confirm_my_rates()'),
               ('set_photo_consent', 'public.set_photo_consent(boolean,text)')) as f(name, sig);

-- 5) The two triggers. Expected / Esperado: 2 rows (before insert or update or delete, each row)
select t.tgname, c.relname as table_name, pg_get_triggerdef(t.oid) as definition
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where t.tgname in ('acceptance_gate_profile_revisions', 'acceptance_gate_location_requests') and not t.tgisinternal;

-- 6) The four replaced functions carry the gate. Expected / Esperado: 4 rows, calls_gate = true
select p.proname, pg_get_functiondef(p.oid) like '%assert_current_acceptances%' as calls_gate
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('submit_revision', 'update_my_rates', 'confirm_my_rates', 'set_photo_consent')
 order by p.proname;

-- 7) TURN THE GATE ON (changes data; only after the banner is deployed). In one transaction, with a check.
--    ENCENDER LA PUERTA (cambia datos; solo con el aviso desplegado). En una sola transacción, con control.
--    The minimums are the versions in src/lib/legal/versions.ts today. To turn it OFF: set minimum_version = null.
--    Los mínimos son las versiones de src/lib/legal/versions.ts hoy. Para APAGARLA: minimum_version = null.
-- begin;
-- update public.legal_document_types
--    set minimum_version = case code when 'terms' then '2026-11-e' when 'privacy' then '2026-11-e' when 'legal_declaration' then '2026-11-a' end
--  where code in ('terms', 'privacy', 'legal_declaration');
-- select code, minimum_version from public.legal_document_types order by sort_order;  -- 3 with a value, 2 null
-- commit;
