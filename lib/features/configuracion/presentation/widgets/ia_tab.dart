import 'package:flutter/material.dart';

import '../../../../core/config/ia_config.dart';

/// Pestaña de Ajustes para la clave de IA (Gemini) que usa el alta de activos
/// por foto.
///
/// La clave se guarda cifrada en el dispositivo; acá solo se configura, no se
/// muestra completa ni se envía a la base.
class IaTab extends StatefulWidget {
  const IaTab({super.key});

  @override
  State<IaTab> createState() => _IaTabState();
}

class _IaTabState extends State<IaTab> {
  final _ia = IaConfig();
  final _claveCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();

  bool _cargando = true;
  bool _hayClave = false;
  bool _verClave = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _claveCtrl.dispose();
    _modeloCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final hay = await _ia.hayClave();
      final modelo = await _ia.leerModelo();
      if (!mounted) return;
      setState(() {
        _hayClave = hay;
        _modeloCtrl.text = modelo;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('No se pudo leer la configuración de IA', '$e');
    }
  }

  Future<void> _guardar() async {
    final clave = _claveCtrl.text.trim();
    if (clave.isEmpty && !_hayClave) {
      _aviso(
        'Falta la clave',
        'Escribí la clave de API de Gemini para usar la identificación por foto.',
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      if (clave.isNotEmpty) await _ia.guardarClave(clave);
      await _ia.guardarModelo(_modeloCtrl.text);
      final hay = await _ia.hayClave();
      if (!mounted) return;
      setState(() {
        _hayClave = hay;
        _guardando = false;
        _claveCtrl.clear();
        _verClave = false;
      });
      _aviso(
        'Listo',
        'La configuración de IA quedó guardada en este dispositivo.',
        exito: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso('No se pudo guardar', '$e');
    }
  }

  Future<void> _borrar() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar la clave'),
        content: const Text(
          'La identificación de activos por foto dejará de funcionar hasta '
          'que cargues otra clave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ia.borrarClave();
      if (!mounted) return;
      setState(() => _hayClave = false);
      _aviso(
        'Clave borrada',
        'Ya no hay clave de IA guardada en este dispositivo.',
        exito: true,
      );
    } catch (e) {
      if (!mounted) return;
      _aviso('No se pudo borrar', '$e');
    }
  }

  void _aviso(String titulo, String detalle, {bool exito = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$titulo. $detalle'),
        duration: Duration(seconds: exito ? 3 : 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Identificación de activos por foto',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Desde Activos, el botón de cámara toma una foto del '
                      'artículo y la manda a Gemini (Google) para identificar '
                      'la marca, el modelo y un valor de referencia. Después '
                      'revisás y confirmás antes de guardar.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'La foto no se guarda. Requiere internet y una clave de '
                      'API propia; el plan gratuito tiene límites y el uso '
                      'intensivo puede tener costo.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _EstadoClave(hayClave: _hayClave),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _claveCtrl,
                      obscureText: !_verClave,
                      decoration: InputDecoration(
                        labelText: _hayClave
                            ? 'Cambiar la clave de API'
                            : 'Clave de API de Gemini',
                        hintText: _hayClave
                            ? 'Dejalo vacío para conservar la actual'
                            : 'AIza…',
                        suffixIcon: IconButton(
                          tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                          icon: Icon(
                            _verClave
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _verClave = !_verClave),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modeloCtrl,
                      decoration: InputDecoration(
                        labelText: 'Modelo',
                        helperText:
                            'Por defecto: ${IaConfig.modeloPorDefecto}',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _guardando ? null : _guardar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_guardando ? 'Guardando…' : 'Guardar'),
                        ),
                        if (_hayClave)
                          TextButton.icon(
                            onPressed: _guardando ? null : _borrar,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.error,
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Borrar clave'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Podés crear una clave en aistudio.google.com/apikey',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EstadoClave extends StatelessWidget {
  const _EstadoClave({required this.hayClave});

  final bool hayClave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hayClave ? scheme.tertiary : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          hayClave ? Icons.check_circle_outline : Icons.info_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hayClave
                ? 'Hay una clave guardada en este dispositivo.'
                : 'Todavía no hay una clave configurada.',
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
