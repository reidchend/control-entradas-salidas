import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../core/config/ia_config.dart';
import '../../../../core/ia/gemini_cuota.dart';
import '../../../../core/ia/gemini_vision.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/cuota_gemini_linea.dart';
import '../../data/activo_identificado.dart';
import '../../data/identificar_activo.dart';

/// Ancho máximo al que se achica la foto antes de mandarla a la IA.
///
/// Una foto de cámara completa pesa varios MB y no aporta detalle útil: con
/// 1280 px el envío es rápido y barato, y el modelo sigue leyendo etiquetas.
const _anchoMaximo = 1280;

/// Abre la cámara (teléfono) o el selector de archivos (escritorio), manda la
/// foto a Gemini y devuelve los datos propuestos del artículo.
///
/// Devuelve `null` si el usuario cancela o si no se pudo tomar la foto. No
/// registra nada: el llamador decide qué hacer con los datos.
Future<ActivoIdentificado?> identificarActivoConFoto(
  BuildContext context,
) async {
  final ia = IaConfig();

  var clave = await ia.leerClave();
  if (clave == null) {
    if (!context.mounted) return null;
    clave = await showDialog<String>(
      context: context,
      builder: (_) => const _ClaveIaDialog(),
    );
    if (clave == null) return null;
    await ia.guardarClave(clave);
  }
  final apiKey = clave;
  if (apiKey == null) return null;
  final modelo = await ia.leerModelo();

  Uint8List? foto;
  try {
    foto = await _tomarFoto();
  } catch (e) {
    if (!context.mounted) return null;
    await _aviso(
      context,
      'No se pudo tomar la foto',
      e is IaException
          ? e.mensaje
          : 'Revisá el permiso de cámara de la app e intentá de nuevo.',
    );
    return null;
  }
  if (foto == null || !context.mounted) return null;
  final imagen = foto;

  return showDialog<ActivoIdentificado>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _IdentificarDialog(
      foto: imagen,
      apiKey: apiKey,
      modelo: modelo,
    ),
  );
}

/// Cámara trasera en Android/iOS; en escritorio se elige una foto del equipo
/// (el plugin de cámara no existe para Windows).
Future<Uint8List?> _tomarFoto() async {
  final esTelefono = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  XFile? archivo;
  if (esTelefono) {
    archivo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 1600,
      imageQuality: 90,
    );
  } else {
    archivo = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Imágenes',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
  }
  if (archivo == null) return null;
  return _prepararImagen(await archivo.readAsBytes());
}

/// Orienta, achica y recomprime a JPEG para que el envío sea liviano.
Uint8List _prepararImagen(Uint8List original) {
  final decodificada = img.decodeImage(original);
  if (decodificada == null) {
    throw const IaException(
      'No se pudo leer la imagen. Probá con una foto JPG o PNG.',
    );
  }
  final orientada = img.bakeOrientation(decodificada);
  final redimensionada = orientada.width > _anchoMaximo
      ? img.copyResize(orientada, width: _anchoMaximo)
      : orientada;
  return Uint8List.fromList(img.encodeJpg(redimensionada, quality: 85));
}

Future<void> _aviso(BuildContext context, String titulo, String detalle) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(detalle),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Diálogo de identificación
// ---------------------------------------------------------------------------

class _IdentificarDialog extends StatefulWidget {
  const _IdentificarDialog({
    required this.foto,
    required this.apiKey,
    required this.modelo,
  });

  final Uint8List foto;
  final String apiKey;
  final String modelo;

  @override
  State<_IdentificarDialog> createState() => _IdentificarDialogState();
}

class _IdentificarDialogState extends State<_IdentificarDialog> {
  ActivoIdentificado? _resultado;
  String? _error;
  bool _enviando = true;

  /// Contador local de cuota: se abre una vez y se usa en cada reintento.
  GeminiCuota? _cuota;

  @override
  void initState() {
    super.initState();
    _identificar();
  }

  Future<void> _identificar() async {
    setState(() {
      _enviando = true;
      _error = null;
      _resultado = null;
    });
    final cuota = _cuota ??= await GeminiCuota.abrir();
    try {
      final datos = await identificarActivoDesdeFoto(
        imagen: widget.foto,
        apiKey: widget.apiKey,
        modelo: widget.modelo,
        cuota: cuota,
      );
      if (!mounted) return;
      setState(() {
        _resultado = datos;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is IaException ? e.mensaje : 'Error inesperado: $e';
        _enviando = false;
      });
    }
  }

  /// Línea de cupo que se ve bajo el resultado, para que no sorprenda el 429.
  Widget? get _cupoHoy {
    final cuota = _cuota;
    if (cuota == null) return null;
    final modelo = cuota.ultimoModelo();
    if (modelo == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CuotaGeminiLinea(
        modelo: modelo,
        usadas: cuota.usadas(modelo),
        limite: cuota.limite(modelo),
        reinicio: cuota.proximoReinicio(),
        compacta: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Se construye una sola vez por frame; el getter arma el widget.
    final cupoHoy = _enviando ? null : _cupoHoy;
    return AlertDialog(
      title: const Text('Identificar con IA'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  widget.foto,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              if (_enviando) ...[
                LinearProgressIndicator(
                  color: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 12),
                Text(
                  'Analizando la foto…',
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  'Puede tardar hasta un minuto.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ] else if (_error != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se pudo identificar',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ] else if (_resultado != null)
                _Resultado(datos: _resultado!),
              if (cupoHoy != null) cupoHoy,
            ],
          ),
        ),
      ),
      actions: [
        if (_enviando)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          )
        else if (_error != null) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: _identificar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ] else if (_resultado != null) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _resultado),
            icon: const Icon(Icons.check),
            label: const Text('Usar estos datos'),
          ),
        ],
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.datos});

  final ActivoIdentificado datos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final confianza = datos.confianza;
    final color = confianza >= 0.7
        ? appColor(context, 'success')
        : confianza >= 0.4
            ? appColor(context, 'warning')
            : scheme.error;
    final detalle = [
      if (datos.marca.isNotEmpty) datos.marca,
      if (datos.modelo.isNotEmpty) datos.modelo,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          datos.nombre,
          style: texto.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (detalle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            detalle,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (datos.grupo.isNotEmpty)
              _Etiqueta(icono: Icons.category_outlined, texto: datos.grupo),
            if (datos.categoria.isNotEmpty)
              _Etiqueta(icono: Icons.folder_outlined, texto: datos.categoria),
            if (datos.valorEstimadoUsd > 0)
              _Etiqueta(
                icono: Icons.sell_outlined,
                texto: 'USD ${datos.valorEstimadoUsd.toStringAsFixed(2)}',
              ),
          ],
        ),
        if (datos.descripcion.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            datos.descripcion,
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              'Confianza ${(confianza * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Revisá y corregí los datos antes de guardar.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clave de API (primera vez)
// ---------------------------------------------------------------------------

class _ClaveIaDialog extends StatefulWidget {
  const _ClaveIaDialog();

  @override
  State<_ClaveIaDialog> createState() => _ClaveIaDialogState();
}

class _ClaveIaDialogState extends State<_ClaveIaDialog> {
  final _ctrl = TextEditingController();
  bool _ver = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _guardar() {
    final clave = _ctrl.text.trim();
    if (clave.isEmpty) {
      setState(() => _error = 'Escribí la clave de API');
      return;
    }
    Navigator.pop(context, clave);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Clave de Gemini'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para identificar artículos por foto, la app usa Gemini (Google). '
              'Necesita una clave de API propia: se guarda cifrada en este '
              'dispositivo y no se comparte.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Podés crearla en aistudio.google.com/apikey',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              obscureText: !_ver,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Clave de API',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: _ver ? 'Ocultar' : 'Mostrar',
                  icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _ver = !_ver),
                ),
              ),
              onSubmitted: (_) => _guardar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
