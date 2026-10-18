/// Ticket de comanda ESC/POS (port de `usr/pos/printer.py` -> `_escpos_ticket`).
///
/// Genera los bytes ESC/POS para una impresora térmica (NT-5890K y
/// compatibles) y también una vista previa textual de 32 columnas para la
/// versión web. No toca la base de datos: el correlativo/header se resuelven
/// fuera (ver `ticket_settings.dart`).
library;

import 'pos_comanda_models.dart' show formatearBs, formatearTasa;

/// Membrete de comanda (pos_settings `comanda_header_*`).
class TicketHeader {
  const TicketHeader({
    this.nombre = '',
    this.rif = '',
    this.direccion = '',
    this.telefono = '',
    this.size = 'large',
  });

  final String nombre;
  final String rif;
  final String direccion;
  final String telefono;

  /// 'small' | 'normal' | 'large' (pos_settings `comanda_header_size`).
  final String size;

  TicketHeader copyWith({
    String? nombre,
    String? rif,
    String? direccion,
    String? telefono,
    String? size,
  }) {
    return TicketHeader(
      nombre: nombre ?? this.nombre,
      rif: rif ?? this.rif,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      size: size ?? this.size,
    );
  }
}

/// Línea de ítem para el ticket.
typedef TicketItem = ({
  int cantidad,
  String nombre,
  double precio,
  List<String> contornos,
});

const int ticketCols = 32;

/// Formatea `cant` como Python `f"{cant:g}"` (sin ceros a la derecha).
String _formatearCantidad(num cant) {
  if (cant == cant.roundToDouble() && cant.abs() < 1e12) {
    return cant.toInt().toString();
  }
  var s = cant.toString();
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

String _fechaHoraActual() {
  final now = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(now.day)}/${p(now.month)}/${now.year} ${p(now.hour)}:${p(now.minute)}';
}

/// Construye los bytes ESC/POS del ticket (port exacto de `_escpos_ticket`).
List<int> construirTicketEscpos({
  required List<TicketItem> items,
  double? total,
  int? comandaId,
  int? correlativo,
  int? correccionDe,
  double? tasa,
  String? cajero,
  String? mesa,
  String? habitacion,
  String? cliente,
  required TicketHeader header,
  String fecha = '',
  bool esCopiaCliente = false,
  bool esComandaCocina = false,
}) {
  final cmd = <int>[];

  void add(List<int> b) => cmd.addAll(b);
  void text(String s) => add(s.codeUnits);
  void newline() => add([0x0a]);

  add([0x1b, 0x40]); // inicializar

  // --- Membrete / Header ---
  final nombreEmpresa = header.nombre.trim();
  final rif = header.rif.trim();
  final direccion = header.direccion.trim();
  final telefono = header.telefono.trim();
  final headerSize = header.size;

  add([0x1b, 0x61, 0x01]); // centrar
  if (headerSize == 'small') {
    add([0x1b, 0x21, 0x01]); // font B (condensado)
  } else if (headerSize == 'normal') {
    add([0x1b, 0x21, 0x00]); // normal
  }
  if (nombreEmpresa.isNotEmpty) {
    if (headerSize == 'large') {
      add([0x1b, 0x21, 0x30]); // doble altura + doble ancho
    }
    text(nombreEmpresa);
    newline();
    add([0x1b, 0x21, 0x00]); // reset char size
  }
  if (headerSize == 'small') {
    add([0x1b, 0x21, 0x01]);
  }
  if (rif.isNotEmpty) {
    text('RIF: $rif');
    newline();
  }
  if (direccion.isNotEmpty) {
    text(direccion);
    newline();
  }
  if (telefono.isNotEmpty) {
    text('Tel: $telefono');
    newline();
  }
  if (headerSize == 'small') {
    add([0x1b, 0x21, 0x00]);
  }

  // Correlativo
  add([0x1b, 0x61, 0x00]); // izquierda
  if (comandaId != null) {
    final corr = correlativo ?? 0;
    add([0x1b, 0x45, 0x01]); // negrita on
    text('Comanda Nro: ${corr.toString().padLeft(5, '0')}');
    newline();
    add([0x1b, 0x45, 0x00]); // negrita off
    if (correccionDe != null) {
      add([0x1b, 0x45, 0x01]);
      text('* CORRECCION DE COMANDA ${correccionDe.toString().padLeft(5, '0')} *');
      newline();
      add([0x1b, 0x45, 0x00]);
    }
  }

  add([0x1b, 0x61, 0x00]);
  text(fecha.isEmpty ? _fechaHoraActual() : fecha);
  newline();
  if (esComandaCocina) {
    add([0x1b, 0x61, 0x02]); // derecha
    add([0x1b, 0x45, 0x01]);
    text('PARA COCINA');
    newline();
    add([0x1b, 0x45, 0x00]);
    add([0x1b, 0x61, 0x00]); // izquierda
  } else if (esCopiaCliente) {
    add([0x1b, 0x61, 0x02]);
    add([0x1b, 0x45, 0x01]);
    text('COPIA CLIENTE');
    newline();
    add([0x1b, 0x45, 0x00]);
    add([0x1b, 0x61, 0x00]);
  }
  if (cajero != null && cajero.isNotEmpty) {
    text('Cajero: $cajero');
    newline();
  }
  if (mesa != null && mesa.isNotEmpty) {
    text('Mesa: $mesa');
    newline();
  }
  if (habitacion != null && habitacion.isNotEmpty) {
    text('Hab.: $habitacion');
    newline();
  }
  if (cliente != null && cliente.isNotEmpty) {
    text('Cliente: $cliente');
    newline();
  }
  text('-' * ticketCols);
  newline();
  newline();

  for (final item in items) {
    final cantStr = '${_formatearCantidad(item.cantidad)}x ';
    final subtotal = item.precio * item.cantidad;
    final precioStr = esComandaCocina ? '' : '\$${subtotal.toStringAsFixed(2)}';
    var nombre =
        item.nombre.substring(0, item.nombre.isNotEmpty ? item.nombre.length : 0);
    final maxNombre = esComandaCocina
        ? (ticketCols - cantStr.length)
        : (ticketCols - precioStr.length - 1 - cantStr.length);
    if (nombre.length > maxNombre && maxNombre > 0) {
      nombre = nombre.substring(0, maxNombre);
    }
    final izquierda = cantStr + nombre;
    final relleno = esComandaCocina
        ? 0
        : (ticketCols - izquierda.length - precioStr.length);

    add([0x1b, 0x45, 0x01]);
    text(cantStr);
    add([0x1b, 0x45, 0x00]);
    text(nombre);
    if (!esComandaCocina) {
      add(List.filled(relleno > 0 ? relleno : 0, 0x20));
      add([0x1b, 0x45, 0x01]);
      text(precioStr);
      add([0x1b, 0x45, 0x00]);
    }
    newline();

    for (final c in item.contornos) {
      text('   + $c');
      newline();
    }
  }

  text('-' * ticketCols);
  newline();

  // El total en $ se imprime siempre (también en la comanda de cocina) para
  // que ambos tickets de cobro sean iguales: Bs ya salía incondicionalmente.
  if (total != null) {
    add([0x1b, 0x61, 0x02]); // derecha
    add([0x1b, 0x45, 0x01]);
    text('TOTAL: \$${total.toStringAsFixed(2)}');
    newline();
    add([0x1b, 0x45, 0x00]);
    add([0x1b, 0x61, 0x00]);
  }

  if (total != null && tasa != null && tasa > 0) {
    add([0x1b, 0x61, 0x02]);
    text('Tasa: ${formatearTasa(tasa)} Bs/\$');
    newline();
    add([0x1b, 0x45, 0x01]);
    text('TOTAL Bs: ${formatearBs(total * tasa)}');
    newline();
    add([0x1b, 0x45, 0x00]);
    add([0x1b, 0x61, 0x00]);
  }

  if (esComandaCocina) {
    newline();
    add([0x1b, 0x61, 0x02]);
    add([0x1b, 0x45, 0x01]);
    text('*** PARA COCINA ***');
    newline();
    add([0x1b, 0x45, 0x00]);
    add([0x1b, 0x61, 0x00]);
  }

  newline();
  add([0x1b, 0x64, 0x04]); // avanzar 4 líneas
  add([0x1d, 0x56, 0x00]); // corte parcial
  return cmd;
}

/// Centra `texto` dentro de `ancho` columnas.
String _centrar(String texto, int ancho) {
  if (texto.length >= ancho) return texto;
  final izq = (ancho - texto.length) ~/ 2;
  return '${' ' * izq}$texto';
}

/// Alinea `texto` a la derecha dentro de `ancho` columnas.
String _derecha(String texto, int ancho) {
  if (texto.length >= ancho) return texto;
  return '${' ' * (ancho - texto.length)}$texto';
}

/// Vista previa textual (32 columnas, monospace) del ticket, para la web.
/// Port de la salida de `_escpos_ticket` a texto plano.
List<String> construirTicketPreview({
  required List<TicketItem> items,
  double? total,
  int? comandaId,
  int? correlativo,
  int? correccionDe,
  double? tasa,
  String? cajero,
  String? mesa,
  String? habitacion,
  String? cliente,
  required TicketHeader header,
  String fecha = '',
  bool esCopiaCliente = false,
  bool esComandaCocina = false,
}) {
  final lineas = <String>[];

  final nombreEmpresa = header.nombre.trim();
  final rif = header.rif.trim();
  final direccion = header.direccion.trim();
  final telefono = header.telefono.trim();

  if (nombreEmpresa.isNotEmpty) lineas.add(_centrar(nombreEmpresa, ticketCols));
  if (rif.isNotEmpty) lineas.add(_centrar('RIF: $rif', ticketCols));
  if (direccion.isNotEmpty) lineas.add(_centrar(direccion, ticketCols));
  if (telefono.isNotEmpty) lineas.add(_centrar('Tel: $telefono', ticketCols));

  if (esCopiaCliente) {
    lineas.add(_centrar('COPIA CLIENTE', ticketCols));
  }
  if (esComandaCocina) {
    lineas.add(_centrar('COCINA - PARA COCINA', ticketCols));
  }

  if (comandaId != null) {
    final corr = correlativo ?? 0;
    lineas.add('Comanda Nro: ${corr.toString().padLeft(5, '0')}');
    if (correccionDe != null) {
      lineas.add('* CORRECCION DE COMANDA ${correccionDe.toString().padLeft(5, '0')} *');
    }
  }

  lineas.add(fecha.isEmpty ? _fechaHoraActual() : fecha);
  if (cajero != null && cajero.isNotEmpty) lineas.add('Cajero: $cajero');
  if (mesa != null && mesa.isNotEmpty) lineas.add('Mesa: $mesa');
  if (habitacion != null && habitacion.isNotEmpty) lineas.add('Hab.: $habitacion');
  if (cliente != null && cliente.isNotEmpty) lineas.add('Cliente: $cliente');
  lineas.add('-' * ticketCols);

  for (final item in items) {
    final cantStr = '${_formatearCantidad(item.cantidad)}x ';
    final subtotal = item.precio * item.cantidad;
    final precioStr = '\$${subtotal.toStringAsFixed(2)}';
    var nombre = item.nombre;
    final maxNombre = ticketCols - precioStr.length - 1 - cantStr.length;
    if (nombre.length > maxNombre) nombre = nombre.substring(0, maxNombre);
    final izquierda = cantStr + nombre;
    final relleno = ticketCols - izquierda.length - precioStr.length;
    lineas.add('$izquierda${' ' * relleno}$precioStr');
    for (final c in item.contornos) {
      lineas.add('   + $c');
    }
  }

  lineas.add('-' * ticketCols);

  if (total != null) {
    lineas.add(_derecha('TOTAL: \$${total.toStringAsFixed(2)}', ticketCols));
    if (tasa != null && tasa > 0) {
      lineas.add(_derecha('Tasa: ${formatearTasa(tasa)} Bs/\$', ticketCols));
      lineas.add(_derecha('TOTAL Bs: ${formatearBs(total * tasa)}', ticketCols));
    }
  }

  lineas.add('');
  return lineas;
}
