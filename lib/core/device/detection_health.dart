/// La detección está apagada cuando ni el proceso de la pantalla ni el
/// servicio en segundo plano están recibiendo ubicación.
/// Un error al arrancar se muestra enseguida. Si todavía está arrancando,
/// se espera hasta [suppressUntil] para no asustar al abrir.
bool detectionLooksOff({
  required bool kid,
  required bool permissionsReady,
  required bool inProcessRunning,
  required bool taskRunning,
  required bool hasStartError,
  required DateTime now,
  required DateTime suppressUntil,
}) {
  if (!kid || !permissionsReady) return false;
  if (inProcessRunning || taskRunning) return false;
  if (hasStartError) return true;
  if (now.isBefore(suppressUntil)) return false;
  return true;
}

/// El servicio en primer plano es el dueño. Si no está, hay que prender
/// la detección en este proceso.
bool shouldRestartInProcessDetection({
  required bool serviceRunning,
  required bool inProcessRunning,
}) {
  return !serviceRunning && !inProcessRunning;
}
