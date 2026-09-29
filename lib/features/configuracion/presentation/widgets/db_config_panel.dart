import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/db_config.dart';
import '../../../../core/network/postgres_client.dart';

/// Panel de configuración de la conexión a PostgreSQL.
///
/// En Windows y Android la app abre un socket directo a la base, así que el
/// host/puerto/usuario se defines acá y quedan guardados en el dispositivo.
/// Es la vía soportada para apuntar a la base local del servidor sin tener
/// que recompilar la app en cada cambio de IP.
///
/// En web no aplica: la conexión pasa por el proxy `/proxy-sql` del servidor.
class DbConfigPanel extends ConsumerStatefulWidget {
  const DbConfigPanel({super.key});

  @override
  ConsumerState<DbConfigPanel> createState() => _DbConfigPanelState();
}

class _DbConfigPanelState extends ConsumerState<DbConfigPanel> {
  final _formKey = GlobalKey<FormState>();
  final _hostCtrl = TextEditingController();
  final _puertoCtrl = TextEditingController(text: '5432');
  final _dbCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _ssl = false;
  bool _cargando = true;
  bool _probando = false;
  String _resultado = '';
  Color? _resultadoColor;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _puertoCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final config = await DbConfig.load();
      if (config != null) {
        _hostCtrl.text = config.host;
        _puertoCtrl.text = '${config.port}';
        _dbCtrl.text = config.database;
        _userCtrl.text = config.user;
        _passCtrl.text = config.password;
        _ssl = config.ssl;
      } else {
        final url = await resolveDatabaseUrl();
        final uri = url.isEmpty ? null : Uri.tryParse(url);
        if (uri != null) {
          _hostCtrl.text = uri.host;
          _puertoCtrl.text = uri.hasPort ? '${uri.port}' : '5432';
          _dbCtrl.text = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
          _userCtrl.text = uri.userInfo.split(':').first;
          _ssl = uri.queryParameters['sslmode'] == 'require';
        }
      }
    } on DbConfigStorageError catch (e) {
      // El formulario queda vacío y usable: el usuario puede reescribir la
      // configuración para recuperase.
      _resultado = e.message;
      _resultadoColor = Colors.red;
    }
    if (mounted) setState(() => _cargando = false);
  }

  DbConfig? _leerForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return DbConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_puertoCtrl.text.trim()) ?? 5432,
      database: _dbCtrl.text.trim(),
      user: _userCtrl.text.trim(),
      password: _passCtrl.text,
      ssl: _ssl,
    );
  }

  Future<void> _guardar() async {
    final config = _leerForm();
    if (config == null) return;
    try {
      await DbConfig.save(config);
    } on DbConfigStorageError catch (e) {
      _error(e.message);
      return;
    }
    if (!mounted) return;
    // Forces the re-pool so the app picks up the new connection.
    ref.invalidate(postgresPoolProvider);
    _ok('Configuración guardada. Reiniciá la app para aplicarla.');
  }

  Future<void> _probar() async {
    final config = _leerForm();
    if (config == null) return;
    setState(() {
      _probando = true;
      _resultado = 'Probando…';
      _resultadoColor = null;
    });
    try {
      await config.test();
      if (!mounted) return;
      setState(() {
        _resultado = 'Conexión correcta';
        _resultadoColor = Colors.green;
        _probando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultado = 'Error: $e';
        _resultadoColor = Colors.red;
        _probando = false;
      });
    }
  }

  Future<void> _borrar() async {
    try {
      await DbConfig.clear();
    } on DbConfigStorageError catch (e) {
      _error(e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(postgresPoolProvider);
    _hostCtrl.clear();
    _dbCtrl.clear();
    _userCtrl.clear();
    _passCtrl.clear();
    _puertoCtrl.text = '5432';
    setState(() {
      _ssl = false;
      _resultado = 'Configuración borrada. Se usará la del binario.';
      _resultadoColor = Colors.orange;
    });
  }

  void _ok(String msg) => setState(() {
        _resultado = msg;
        _resultadoColor = Colors.green;
      });

  void _error(String msg) => setState(() {
        _resultado = msg;
        _resultadoColor = Colors.red;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Base de datos',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Conexión directa a PostgreSQL (Windows y Android).',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          'En web no aplica: la conexión pasa por el proxy del servidor.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: '100.x.y.z (Tailscale) o localhost',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _dbCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base de datos',
                        hintText: 'control_entradas',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _puertoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Puerto',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final p = int.tryParse((v ?? '').trim());
                        if (p == null || p < 1 || p > 65535) {
                          return 'Inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ssl,
                onChanged: (v) => setState(() => _ssl = v),
                title: const Text('Usar SSL', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  'Con Tailscale activalo: el tráfico ya va cifrado.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _probando ? null : _probar,
              icon: _probando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Probar conexión'),
            ),
            FilledButton.tonalIcon(
              onPressed: _guardar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
            TextButton.icon(
              onPressed: _borrar,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar'),
            ),
          ],
        ),
        if (_resultado.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _resultado,
            style: TextStyle(
              color: _resultadoColor ?? scheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }
}
