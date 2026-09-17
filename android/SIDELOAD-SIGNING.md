# Firma sideload (instalar encima sin perder datos)

## Evidencia del wipe histórico

1. **applicationId** siempre fue `com.llegue.llegue_mobile` (no era el problema).
2. **Firma:** `buildTypes.release` usaba `signingConfigs.debug`. El debug keystore
   es por máquina/usuario. Si el APK se genera en otro entorno, Android exige
   desinstalar → borra SharedPreferences (sesión/familia).
3. **Bootstrap:** ante 401 (p. ej. SQLite de Render vacío tras redeploy) se llamaba
   `logout()` → `clearSession()`. Eso también “parecía” wipe al actualizar aunque
   la firma coincidiera.
4. **No** hay reset de prefs por `versionCode`.

## Cert fijo (esta PC / Enzo)

- Archivo: `android/sideload.keystore` (copia fija; **no regenerar**).
- Props: `android/key.properties` (gitignored).
- Backup: `D:\Documents\Prueba de Cursor\llegue-signing\`
- SHA1 actual: `6D:6A:0D:E8:CE:A8:C6:00:80:0F:36:94:D6:04:07:1A:98:6B:1B:7F`

Si perdés el keystore, no hay forma de actualizar encima: hay que desinstalar.

## Checklist manual

1. Instalar APK N.
2. Entrar, cargar familia.
3. Instalar APK N+1 **encima** (sin desinstalar).
4. Abrir app → misma familia, sin OTP de nuevo.
5. Modo avión → cold start → sigue “adentro” con datos locales.
