import 'printer_service.dart' show puedeImprimirNativo;

/// Permisos del POS según el dispositivo.
///
/// La "PC principal" es el único equipo con impresora térmica y envío RAW
/// (hoy Windows nativo). Desde ahí se abre y se cierra el turno y se cobran
/// las comandas; los Android solo se unen al turno y operan (comandas, mesas,
/// inventario), pero no cobran ni cierran.
///
/// Se apoya en `puedeImprimirNativo` (no en `dart:io` directo) para que el
/// build web siga compilando: en web y Android vale `false`.
bool get esPcPrincipal => puedeImprimirNativo;

/// Cobrar una comanda (y por lo tanto emitir ticket) solo en la PC principal.
bool get puedeCobrar => esPcPrincipal;

/// Abrir un turno nuevo solo desde la PC principal.
bool get puedeAbrirTurno => esPcPrincipal;

/// Cerrar el turno: solo el aperturista y solo desde la PC principal.
bool puedeCerrarTurno(bool esAperturista) => esPcPrincipal && esAperturista;
