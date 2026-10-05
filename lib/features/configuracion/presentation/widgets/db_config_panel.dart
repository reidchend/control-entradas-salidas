import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/db_config.dart';
import '../../../../core/data/servidor_discovery_providers.dart';
import '../../../../core/network/postgres_client.dart';
import 'db_fields_directo.dart';
import 'db_fields_proxy.dart';

/// Panel de configuración de la conexión, elegible en runtime.
///
/// Dos modos, según cómo el equipo del cliente llega a la base:
///
/// - **Proxy HTTP** (por defecto): la app habla HTTPS con el servidor, que
///   habla con PostgreSQL. No hay que abrir el 5432 ni instalar Tailscale en
///   el equipo. Cada query es un viaje HTTP.
/// - **TCP directo**: la app abre un pool al 5432. Es más rápido por query,
///   pero exige que el equipo alcance la base por una red privada.
///
/// En web no aplica ninguno: la conexión pasa por el proxy del servidor y el
/// panel no se muestra.
class DbConfigPanel extends ConsumerStatefulWidget {
  const DbConfigPanel({super.key});

  @override
  ConsumerState<DbConfigPanel> createState() => _DbConfigPanelState();
}

/// Cómo llega la app a la base. Proxy primero porque es la opción que no
/// depende de la red del equipo donde corre la app.
enum _ModoConexion { proxy, directo }

class _DbConfigPanelState extends ConsumerState<DbConfigPanel> {
  final _formKey = GlobalKey<FormState>();
  final _proxyUrlCtrl = TextEditingController();
  final _proxyTokenCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _puertoCtrl = TextEditingController(text: '5432');
  final _dbCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  _ModoConexion _modo = _ModoConexion.proxy;
  bool _ssl = false;
  bool _buscandoUrl = false;

  /// Permite escribir la URL a mano. Viene en `false` porque lo normal es que
  /// la app la descubra sola: lo único que el usuario escribe es el token.
  bool _urlEditable = false;
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
    _proxyUrlCtrl.dispose();
    _proxyTokenCtrl.dispose();
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
        _proxyUrlCtrl.text = config.proxyUrl;
        _proxyTokenCtrl.text = config.proxyToken;
        _hostCtrl.text = config.host;
        _puertoCtrl.text = '${config.port}';
        _dbCtrl.text = config.database;
        _userCtrl.text = config.user;
        _passCtrl.text = config.password;
        _ssl = config.ssl;
        if (config.usesProxy) {
          _modo = _ModoConexion.proxy;
          _urlEditable = config.proxyUrlManual;
        } else if (config.host.isNotEmpty) {
          _modo = _ModoConexion.directo;
        }
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

    // En modo proxy la URL se relee del Gist aunque haya una guardada. Con el
    // túnel rápido la URL cambia en cada reinicio del servidor, asi que
    // partir de la guardada era mostrar siempre una direccion que ya no
    // existe. La unica excepcion es una URL escrita a mano, que el usuario
    // fijo a proposito.
    if (_modo == _ModoConexion.proxy && !_urlEditable) {
      await _buscarUrl(silencioso: true);
    }
  }

  /// Busca la URL que el servidor publica en el Gist.
  ///
  /// Es lo que evita ir equipo por equipo cuando el túnel cambia: la app se
  /// entera sola, y el usuario solo tiene que escribir el token.
  Future<void> _buscarUrl({bool silencioso = false}) async {
    if (!silencioso) setState(() => _buscandoUrl = true);
    try {
      final servicio = ref.read(descubridorProvider);
      final url = await servicio.obtenerUrl(forzar: true);
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() {
          _modo = _ModoConexion.proxy;
          _proxyUrlCtrl.text = url;
        });
        _ok('URL encontrada: $url');
      } else {
        // Sin URL no hay nada que probar. Se ofrece escribirla a mano en vez
        // de dejar un campo vacío que no dice qué hacer.
        setState(() => _urlEditable = true);
        // El motivo va delante: el texto que se ponía antes ("verificá el
        // túnel en la PC servidor") asumía que el problema era del servidor, y
        // desde este equipo el servidor no tiene nada que ver. Con el antivirus
        // interceptando HTTPS o el IPv6 roto, el Gist sí está bien y la
        // lectura igual no llega.
        final fallo = servicio.ultimoFallo;
        _error(
          fallo == null
              ? 'No se pudo encontrar la URL. Verificá que el túnel esté '
                  'corriendo en la PC servidor y que tenga GITHUB_TOKEN '
                  'configurado. Mientras tanto podés escribirla a mano.'
              : 'No se pudo encontrar la URL. ${fallo.mensaje} '
                  'Mientras tanto podés escribirla a mano.',
        );
      }
    } catch (e) {
      if (mounted) _error('No se pudo buscar la URL: $e');
    } finally {
      if (mounted && !silencioso) setState(() => _buscandoUrl = false);
    }
  }

  /// Cambia entre proxy y TCP directo.
  ///
  /// Al pasar a proxy sin URL cargada (por ejemplo viniendo de un perfil TCP
  /// directo) se dispara la búsqueda, porque el campo es de solo lectura y si
  /// no, quedaría bloqueado sin forma de salir.
  Future<void> _cambiarModo(_ModoConexion modo) async {
    setState(() => _modo = modo);
    if (modo == _ModoConexion.proxy &&
        _proxyUrlCtrl.text.trim().isEmpty) {
      await _buscarUrl();
    }
  }

  /// Vuelve al modo automático: descarta lo escrito a mano y vuelve a buscar.
  Future<void> _usarUrlAutomatica() async {
    setState(() => _urlEditable = false);
    _proxyUrlCtrl.clear();
    await _buscarUrl();
  }

  DbConfig? _leerForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    if (_modo == _ModoConexion.proxy) {
      return DbConfig(
        host: '',
        port: 5432,
        database: '',
        user: '',
        password: '',
        proxyUrl: _proxyUrlCtrl.text.trim(),
        proxyToken: _proxyTokenCtrl.text,
        // Si el campo estaba en modo edición es porque el usuario escribió la
        // URL (el automático no se abre solo). Se guarda como fija para que la
        // app no la pise con la del Gist en el próximo arranque.
        proxyUrlManual: _urlEditable,
      );
    }
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
    _proxyUrlCtrl.clear();
    _proxyTokenCtrl.clear();
    _hostCtrl.clear();
    _dbCtrl.clear();
    _userCtrl.clear();
    _passCtrl.clear();
    _puertoCtrl.text = '5432';
    setState(() {
      _ssl = false;
      _modo = _ModoConexion.proxy;
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
          'Se aplica a Windows y Android. En web no aplica: la conexión ya pasa '
          'por el proxy del servidor.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        SegmentedButton<_ModoConexion>(
          segments: const [
            ButtonSegment(
              value: _ModoConexion.proxy,
              label: Text('Proxy HTTPS'),
              icon: Icon(Icons.cloud_outlined),
            ),
            ButtonSegment(
              value: _ModoConexion.directo,
              label: Text('TCP directo'),
              icon: Icon(Icons.lan_outlined),
            ),
          ],
          selected: {_modo},
          onSelectionChanged: (s) => _cambiarModo(s.first),
        ),
        const SizedBox(height: 4),
        Text(
          _modo == _ModoConexion.proxy
              ? 'La app consulta por HTTPS al servidor. No necesita Tailscale '
                  'ni abrir el puerto 5432 en este equipo.'
              : 'La app abre una conexión directa a PostgreSQL. El equipo tiene '
                  'que alcanzar el 5432 (Tailscale o red local).',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: _modo == _ModoConexion.proxy
              ? DbFieldsProxy(
                  urlCtrl: _proxyUrlCtrl,
                  tokenCtrl: _proxyTokenCtrl,
                  buscando: _buscandoUrl,
                  urlEditable: _urlEditable,
                  onBuscarUrl: () => _buscarUrl(),
                  onEditarUrl: () => setState(() => _urlEditable = true),
                  onUsarUrlAutomatica: () => _usarUrlAutomatica(),
                )
              : DbFieldsDirecto(
                  hostCtrl: _hostCtrl,
                  puertoCtrl: _puertoCtrl,
                  dbCtrl: _dbCtrl,
                  userCtrl: _userCtrl,
                  passCtrl: _passCtrl,
                  ssl: _ssl,
                  onSslChanged: (v) => setState(() => _ssl = v),
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
