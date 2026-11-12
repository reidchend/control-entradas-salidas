/// Acceso a la configuración de impresión guardada en `pos_settings`
/// (port de `usr/pos/printer.py`): membrete, tamaño del membrete,
/// correlativo de comandas y dispositivo de impresora.
library;

import 'pos_repository.dart';
import 'ticket_escpos.dart';

const String kPrinterDevice = 'printer_device';
const String kComandaHeaderNombre = 'comanda_header_nombre';
const String kComandaHeaderRif = 'comanda_header_rif';
const String kComandaHeaderDireccion = 'comanda_header_direccion';
const String kComandaHeaderTelefono = 'comanda_header_telefono';
const String kComandaCorrelativo = 'comanda_correlativo';
const String kComandaHeaderSize = 'comanda_header_size';
const String kComandaPrecioSize = 'comanda_precio_size';

/// Valida el tamaño del membrete ('small'|'normal'|'large').
String _sizeValido(String? size) {
  return (size == 'small' || size == 'normal' || size == 'large') ? size! : 'large';
}

/// Valida/normaliza el tamaño del precio a '1'-'4'.
String _precioSizeValido(String? size) => normalizarPrecioSize(size);

Future<TicketHeader> cargarMembrete(PosRepository repo) async {
  return TicketHeader(
    nombre: (await repo.getSetting(kComandaHeaderNombre)) ?? '',
    rif: (await repo.getSetting(kComandaHeaderRif)) ?? '',
    direccion: (await repo.getSetting(kComandaHeaderDireccion)) ?? '',
    telefono: (await repo.getSetting(kComandaHeaderTelefono)) ?? '',
    size: _sizeValido(await repo.getSetting(kComandaHeaderSize)),
    precioSize: _precioSizeValido(await repo.getSetting(kComandaPrecioSize)),
  );
}

Future<void> guardarMembrete(
  PosRepository repo, {
  String nombre = '',
  String rif = '',
  String direccion = '',
  String telefono = '',
  String size = 'large',
  String precioSize = '2',
}) async {
  await repo.setSetting(kComandaHeaderNombre, nombre);
  await repo.setSetting(kComandaHeaderRif, rif);
  await repo.setSetting(kComandaHeaderDireccion, direccion);
  await repo.setSetting(kComandaHeaderTelefono, telefono);
  await setHeaderSize(repo, size);
  await setPrecioSize(repo, precioSize);
}

Future<String> getPrecioSize(PosRepository repo) async {
  return _precioSizeValido(await repo.getSetting(kComandaPrecioSize));
}

Future<void> setPrecioSize(PosRepository repo, String precioSize) async {
  await repo.setSetting(kComandaPrecioSize, _precioSizeValido(precioSize));
}

Future<int> getCorrelativoActual(PosRepository repo) async {
  final v = await repo.getSetting(kComandaCorrelativo);
  return int.tryParse(v ?? '') ?? 0;
}

Future<void> setCorrelativoInicial(PosRepository repo, int valor) async {
  await repo.setSetting(kComandaCorrelativo, valor.toString());
}

Future<String> getHeaderSize(PosRepository repo) async {
  return _sizeValido(await repo.getSetting(kComandaHeaderSize));
}

Future<void> setHeaderSize(PosRepository repo, String size) async {
  await repo.setSetting(kComandaHeaderSize, _sizeValido(size));
}

Future<String?> getPrinterDevice(PosRepository repo) async {
  return await repo.getSetting(kPrinterDevice);
}

Future<void> setPrinterDevice(PosRepository repo, String devicePath) async {
  await repo.setSetting(kPrinterDevice, devicePath);
}
