import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/activo_tipo.dart';

/// Qué hacer con el tipo de la unidad al aplicar la identificación.
enum AccionTipo {
  /// Dejar el tipo actual como está.
  ninguna,

  /// Mover solo esta unidad a un tipo que ya existe en el catálogo.
  moverExistente,

  /// Mover solo esta unidad a un tipo nuevo (se crea al guardar).
  moverNuevo,

  /// Corregir nombre/grupo/modelo del tipo actual (afecta a sus unidades).
  corregirActual,
}

/// Cambios que el usuario eligió aplicar tras identificar con IA una unidad
/// existente.
class CambiosIdentificacion {
  const CambiosIdentificacion({
    required this.accion,
    required this.observaciones,
    this.destino,
  });

  final AccionTipo accion;

  /// Agregar el texto reconocido a las observaciones de esta unidad.
  final bool observaciones;

  /// Tipo destino: el existente, el nuevo (id 0) o el actual corregido.
  /// Es `null` cuando [accion] es [AccionTipo.ninguna].
  final ActivoTipo? destino;
}

/// Compara lo que reconoció la IA con lo que ya tiene la unidad y deja elegir
/// qué aplicar.
///
/// [identificado] trae los datos crudos de la IA (id 0). [coincidente] es un
/// tipo del catálogo con el mismo nombre que el reconocido, distinto del
/// actual: si existe, lo más probable es que la unidad esté mal clasificada.
///
/// Devuelve `null` si se cancela. No escribe nada: el formulario sigue abierto
/// y el cambio se confirma recién al guardar.
Future<CambiosIdentificacion?> showAplicarIdentificacionDialog(
  BuildContext context, {
  required ActivoTipo actual,
  required ActivoTipo identificado,
  required ActivoTipo? coincidente,
  required int unidades,
  required String observacionesActuales,
  required String observacionesPropuestas,
}) {
  final corregido = ActivoTipo(
    id: actual.id,
    nombre: identificado.nombre,
    grupo: identificado.grupo ?? actual.grupo,
    modelo: identificado.modelo ?? actual.modelo,
    categoriaId: actual.categoriaId,
    activo: actual.activo,
  );
  final propuesta = observacionesPropuestas.trim();
  final yaIncluida =
      propuesta.isNotEmpty &&
      _normalizar(observacionesActuales).contains(_normalizar(propuesta));

  return showDialog<CambiosIdentificacion>(
    context: context,
    builder: (_) => _AplicarIdentificacionDialog(
      actual: actual,
      identificado: identificado,
      corregido: corregido,
      coincidente: coincidente,
      cambiaActual: _difiere(actual, corregido),
      unidades: unidades,
      observacionesPropuestas: propuesta,
      disponibleObs: propuesta.isNotEmpty && !yaIncluida,
    ),
  );
}

bool _difiere(ActivoTipo a, ActivoTipo b) =>
    _normalizar(a.nombre) != _normalizar(b.nombre) ||
    _normalizar(a.grupo ?? '') != _normalizar(b.grupo ?? '') ||
    _normalizar(a.modelo ?? '') != _normalizar(b.modelo ?? '');

String _normalizar(String s) => s
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp('[áàäâ]'), 'a')
    .replaceAll(RegExp('[éèëê]'), 'e')
    .replaceAll(RegExp('[íìïî]'), 'i')
    .replaceAll(RegExp('[óòöô]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ñ', 'n');

class _AplicarIdentificacionDialog extends StatefulWidget {
  const _AplicarIdentificacionDialog({
    required this.actual,
    required this.identificado,
    required this.corregido,
    required this.coincidente,
    required this.cambiaActual,
    required this.unidades,
    required this.observacionesPropuestas,
    required this.disponibleObs,
  });

  final ActivoTipo actual;
  final ActivoTipo identificado;
  final ActivoTipo corregido;
  final ActivoTipo? coincidente;
  final bool cambiaActual;
  final int unidades;
  final String observacionesPropuestas;
  final bool disponibleObs;

  @override
  State<_AplicarIdentificacionDialog> createState() =>
      _AplicarIdentificacionDialogState();
}

class _AplicarIdentificacionDialogState
    extends State<_AplicarIdentificacionDialog> {
  late AccionTipo _accion;
  late bool _obs;

  @override
  void initState() {
    super.initState();
    // Con un tipo existente del mismo nombre, mover es lo más probable: la
    // unidad estaba mal clasificada y el catálogo ya tiene el bueno. Si el
    // nombre coincide con el actual y solo cambian grupo/modelo, es una
    // corrección del mismo tipo.
    if (widget.coincidente != null) {
      _accion = AccionTipo.moverExistente;
    } else if (widget.cambiaActual &&
        _normalizar(widget.identificado.nombre) ==
            _normalizar(widget.actual.nombre)) {
      _accion = AccionTipo.corregirActual;
    } else {
      _accion = AccionTipo.ninguna;
    }
    _obs = widget.disponibleObs;
  }

  bool get _hayAlgo => _accion != AccionTipo.ninguna || widget.disponibleObs;

  ActivoTipo? get _destino {
    switch (_accion) {
      case AccionTipo.moverExistente:
        return widget.coincidente;
      case AccionTipo.moverNuevo:
        return widget.identificado;
      case AccionTipo.corregirActual:
        return widget.corregido;
      case AccionTipo.ninguna:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coincide = widget.coincidente != null;
    return AlertDialog(
      title: const Text('Aplicar la identificación'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'La IA reconoció «${widget.identificado.nombre}». '
                'Elegí qué aplicar; todavía podés revisarlo antes de guardar.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              const _Seccion('Tipo de la unidad'),
              if (coincide)
                RadioListTile<AccionTipo>(
                  value: AccionTipo.moverExistente,
                  groupValue: _accion,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Mover esta unidad a «${widget.coincidente!.nombre}»',
                  ),
                  subtitle: const Text(
                    'Solo esta unidad; el tipo actual no cambia.',
                  ),
                  onChanged: _elegir,
                ),
              if (!coincide && widget.cambiaActual)
                RadioListTile<AccionTipo>(
                  value: AccionTipo.moverNuevo,
                  groupValue: _accion,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Mover esta unidad a un tipo nuevo '
                    '«${widget.identificado.nombre}»',
                  ),
                  subtitle: const Text(
                    'Se crea en el catálogo al guardar. Solo esta unidad.',
                  ),
                  onChanged: _elegir,
                ),
              if (widget.cambiaActual)
                RadioListTile<AccionTipo>(
                  value: AccionTipo.corregirActual,
                  groupValue: _accion,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Corregir el tipo actual «${widget.actual.nombre}»',
                  ),
                  subtitle: const Text(
                    'Cambia el nombre/grupo/modelo para todas sus unidades.',
                  ),
                  onChanged: _elegir,
                ),
              RadioListTile<AccionTipo>(
                value: AccionTipo.ninguna,
                groupValue: _accion,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('No cambiar el tipo'),
                onChanged: _elegir,
              ),
              if (_accion == AccionTipo.corregirActual) ...[
                const SizedBox(height: 4),
                _Diff(
                  label: 'Nombre',
                  antes: widget.actual.nombre,
                  despues: widget.corregido.nombre,
                ),
                _Diff(
                  label: 'Grupo',
                  antes: widget.actual.grupo ?? '',
                  despues: widget.corregido.grupo ?? '',
                ),
                _Diff(
                  label: 'Modelo',
                  antes: widget.actual.modelo ?? '',
                  despues: widget.corregido.modelo ?? '',
                ),
                if (widget.unidades > 1)
                  _Aviso(
                    'Ese tipo lo comparten ${widget.unidades} unidades '
                    '(incluida esta): el cambio también las afecta.',
                  ),
              ],
              const SizedBox(height: 12),
              const _Seccion('Observaciones'),
              if (widget.disponibleObs) ...[
                CheckboxListTile(
                  value: _obs,
                  onChanged: (v) => setState(() => _obs = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Agregar a las observaciones'),
                  subtitle: const Text(
                    'Se agregan al final, sin borrar lo escrito',
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.observacionesPropuestas,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                ),
              ] else if (widget.observacionesPropuestas.isNotEmpty)
                const _Nota('Las observaciones ya incluyen estos datos.'),
              if (!_hayAlgo) ...[
                const SizedBox(height: 8),
                const _Nota('No hay datos nuevos para aplicar.'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_hayAlgo ? 'Cancelar' : 'Cerrar'),
        ),
        if (_hayAlgo)
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CambiosIdentificacion(
                accion: _accion,
                observaciones: _obs,
                destino: _destino,
              ),
            ),
            child: const Text('Aplicar'),
          ),
      ],
    );
  }

  void _elegir(AccionTipo? v) {
    if (v != null) setState(() => _accion = v);
  }
}

/// Título chico de bloque dentro del diálogo.
class _Seccion extends StatelessWidget {
  const _Seccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Fila "antes → después" de un campo del tipo.
class _Diff extends StatelessWidget {
  const _Diff({
    required this.label,
    required this.antes,
    required this.despues,
  });

  final String label;
  final String antes;
  final String despues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viejo = antes.trim();
    final nuevo = despues.trim();
    if (viejo == nuevo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (viejo.isNotEmpty)
            Text(
              viejo,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  nuevo.isEmpty ? '(vacío)' : nuevo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso ámbar: el cambio alcanza a más de una unidad.
class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final warning = appColor(context, 'warning');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 4, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Texto secundario para los casos "sin cambios".
class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        texto,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
