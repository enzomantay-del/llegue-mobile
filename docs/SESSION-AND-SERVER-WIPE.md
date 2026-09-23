# Sesión inválida

Si el servidor responde 401 (token muerto, JWT cambiado, o el usuario ya no existe), la app **borra** la sesión local (tokens, usuario, familia y lugares) y vuelve al inicio.

Un corte de red o un 5xx **no** borra la sesión: queda el aviso y el botón Reintentar. Si ese reintento termina en 401, ahí sí borra y va al inicio.

Salir de la cuenta hace el mismo borrado local.

## Reinstalar el APK

`android:allowBackup` está en `false` y las reglas de backup excluyen `FlutterSharedPreferences.xml`. Desinstalar e instalar de nuevo **no** debería traer el token viejo.

Si Android igual restaura datos de un backup anterior:

1. Ajustes del celular → Apps → Llegué → Almacenamiento → **Borrar datos** (en los dos celulares).
2. Abrí la app e ingresá de cero.
