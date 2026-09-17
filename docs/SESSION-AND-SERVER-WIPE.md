# Nota API (no se cambia en este PR)

Si Render Free redeploya y SQLite efímero se vacía, `/auth/me` y refresh
devuelven 401 aunque el celular tenga tokens válidos de antes.

Antes la app hacía `logout()` → wipe local (parecía “el APK borró todo”).
Desde 1.0.0+8 la app **conserva** la sesión local y muestra reintento.

Mitigación servidor (fuera de este PR): disco persistente / Starter +
`LLEGUE_DB_PATH`, y `JWT_SECRET` fijo en el dashboard (no regenerar).
