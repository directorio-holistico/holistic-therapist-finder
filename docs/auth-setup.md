# Login setup (email link) / Configuración del ingreso (enlace por mail)

English first, then Spanish. / Primero inglés, después español.

## English

Therapists log in with a one-use link sent by email (no password). Patients never need an account.
Manual steps in the Supabase dashboard and in `.env.local`. No secret goes in the repository.

**Today (default Supabase mailer).** On the free plan with the built-in mailer the email templates are locked ("Set up custom
SMTP to edit templates"), so the default templates are used. The flow is:

1. `.env.local`: `NEXT_PUBLIC_SITE_URL=http://localhost:3000` (the public address of the site; https in production).
2. Dashboard → Authentication → URL Configuration: *Site URL* `http://localhost:3000` and, in *Redirect URLs*,
   `http://localhost:3000/**` (add the production address later).
3. The login form sends the link with `emailRedirectTo = <site>/auth/callback`. Supabase verifies the mail and sends the person to
   `/auth/callback?code=…`, which exchanges the code for a session (PKCE). **It only works in the same browser that asked for the
   link** (it needs that browser's verifier cookie). Opened on another device it shows "the link is not valid" and asks for a new one.
   The same property stops mail scanners from using up the link.

**Before opening to the public (open item, ADR-0002).** Configure a custom SMTP provider: the built-in mailer is for testing only
and has a very low hourly limit [exact value not verified]. With custom SMTP the templates become editable. Then both *Confirm
signup* and *Magic Link* can point to the cross-device page:

```
{{ .SiteURL }}/auth/confirmar?token_hash={{ .TokenHash }}&type=email&next=/mi-perfil
```

That page shows a button; the token is spent only when it is pressed (POST `/auth/verificar`). Both routes stay in the code.

Accounts are created by the login form (`shouldCreateUser`). An account alone gives access to nothing: the profile is created later
by `register_therapist`, which requires a verified email.

How it is protected: the session cookie is `HttpOnly`, `Secure` in production and `SameSite=Lax`; `getUser()` validates the token
with the auth server on every protected page; the `next` destination only accepts paths inside the site; the form answers the same
whether or not the email already exists.

## Español

Los terapeutas ingresan con un enlace de un solo uso enviado por mail (sin contraseña). Los pacientes nunca necesitan cuenta.
Pasos manuales en el panel de Supabase y en `.env.local`. Ningún secreto va en el repositorio.

**Hoy (servicio de mail por defecto de Supabase).** En el plan gratis con el servicio de mail incluido las plantillas están
bloqueadas ("Set up custom SMTP to edit templates"), así que se usan las plantillas por defecto. El flujo es:

1. `.env.local`: `NEXT_PUBLIC_SITE_URL=http://localhost:3000` (la dirección pública del sitio; https en producción).
2. Panel → Authentication → URL Configuration: *Site URL* `http://localhost:3000` y, en *Redirect URLs*,
   `http://localhost:3000/**` (la dirección de producción se suma después).
3. El formulario envía el enlace con `emailRedirectTo = <sitio>/auth/callback`. Supabase verifica el mail y manda a la persona a
   `/auth/callback?code=…`, que cambia el código por una sesión (PKCE). **Solo funciona en el mismo navegador que pidió el enlace**
   (necesita la cookie verificadora de ese navegador). En otro dispositivo muestra "el enlace no es válido" y pide uno nuevo.
   La misma propiedad impide que los escáneres de mail gasten el enlace.

**Antes de abrir al público (pendiente, ADR-0002).** Configurar un SMTP propio: el servicio incluido es solo para pruebas y tiene un
límite por hora muy bajo [valor exacto no verificado]. Con SMTP propio las plantillas se pueden editar. Entonces *Confirm signup*
y *Magic Link* pueden apuntar a la página que sirve entre dispositivos:

```
{{ .SiteURL }}/auth/confirmar?token_hash={{ .TokenHash }}&type=email&next=/mi-perfil
```

Esa página muestra un botón; el token se gasta recién al apretarlo (POST `/auth/verificar`). Las dos rutas quedan en el código.

Las cuentas se crean desde el formulario de ingreso (`shouldCreateUser`). Una cuenta sola no da acceso a nada: el perfil lo crea
después `register_therapist`, que exige mail verificado.

Cómo se protege: la cookie de sesión es `HttpOnly`, `Secure` en producción y `SameSite=Lax`; `getUser()` valida el token con el
servidor de autenticación en cada página protegida; el destino `next` solo acepta rutas del propio sitio; el formulario responde
igual exista o no el mail.
