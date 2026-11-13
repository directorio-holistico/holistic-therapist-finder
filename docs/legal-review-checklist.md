# Legal review checklist / Lista de revisión legal

EN: The legal texts in `src/lib/legal/` are a draft. They must be reviewed by a lawyer before the site opens to the public. While `LEGAL_REVIEW_PENDING` is `true`, every legal page shows a visible notice.
ES: Los textos de `src/lib/legal/` son un borrador. Un abogado debe revisarlos antes de abrir el sitio al público. Mientras `LEGAL_REVIEW_PENDING` sea `true`, cada página legal muestra un aviso visible.

## To verify with a lawyer / Para verificar con un abogado
- [ ] Exact legal name and legal address of the controller (`facts.ts`) / Nombre legal exacto y domicilio del responsable.
- [ ] Contact email in the `CONTROLLER_CONTACT_EMAIL` environment variable / Mail de contacto en la variable de entorno.
- [ ] Registration of the database with the AAIP (Argentina) and the exact mandatory legend of Res. AAIP 14/2018 (use the official wording) / Inscripción de la base ante la AAIP y leyenda oficial obligatoria.
- [ ] International transfers (Supabase in Brazil, Vercel, Cloudflare, mail provider) / Transferencias internacionales.
- [ ] GDPR for visitors and therapists in Spain: legal basis, EU representative if applicable, AEPD / GDPR para España.
- [ ] Mexico: data protection law for therapists in Mexico / México: ley de protección de datos.
- [ ] Consumer-protection wording and liability limits / Consumo y límites de responsabilidad.
- [ ] LNT® trademark wording / Redacción de la marca LNT®.
- [ ] Every statement in the privacy policy matches what the system really does (Turnstile and the contact-reveal route of ADR-0003 must exist, or the text must be changed) / Todo lo que dice la política existe de verdad.
- [ ] Set `LEGAL_REVIEW_PENDING = false` only after the review (tests then require the address) / Pasar a false solo tras la revisión.
