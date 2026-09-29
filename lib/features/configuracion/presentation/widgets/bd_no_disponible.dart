import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/postgres_guard.dart';
import '../../../../core/network/postgres_client.dart';
import '../dialogs/db_config_dialog.dart';

/// Pantalla que reemplaza al login cuando la base no está disponible.
///
/// Existe para romper el círculo del primer arranque: el login lee los cajeros
/// de la base, y la base se configura en un panel que estaba detrás del login.
/// Con esta pantalla, configurar la base es alcanzable sin autenticarse.
///
/// También cubre el caso "estaba configurada y dejó de funcionar" (token
/// vencido, servidor caído), que antes salía como
/// `Error: Null check operator used on a null value`.
class BdNoDisponible extends ConsumerStatefulWidget {
  const BdNoDisponible({super.key});

  @override
  ConsumerState<BdNoDisponible> createState() => _BdNoDisponibleState();
}

class _BdNoDisponibleState extends ConsumerState<BdNoDisponible> {
  bool _reintentando = false;

  Future<void> _configurar() async {
    await showDbConfigDialog(context);
    if (mounted) await _reintentar();
  }

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    // Reconstruye el pool desde cero: si la base estaba caída, la sesión
    // anterior quedó en error y no se reintenta sola.
    ref.invalidate(postgresPoolProvider);
    try {
      await ref.read(postgresPoolProvider.future);
    } catch (_) {
      // El estado real lo muestra el provider; acá solo hay que dejar de
      // girar el indicador.
    } finally {
      if (mounted) setState(() => _reintentando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estado = ref.watch(estadoBdProvider);
    final error = ref.watch(errorConexionBdProvider);

    final esSinConfigurar = estado == EstadoBd.noConfigurada;
    final titulo = esSinConfigurar
        ? 'Base de datos sin configurar'
        : 'No se pudo conectar con la base de datos';
    final mensaje = esSinConfigurar
        ? 'Esta app necesita saber a qué servidor conectarse antes de poder '
            'iniciar sesión. Es un paso que se hace una sola vez por equipo.'
        : 'La configuración está cargada, pero el servidor no respondió. '
            'Revisá que la PC servidor esté encendida y que la URL y el token '
            'siguan vigentes.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                esSinConfigurar
                    ? Icons.storage_outlined
                    : Icons.cloud_off_outlined,
                size: 56,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (!esSinConfigurar && error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _reintentando ? null : _configurar,
                icon: const Icon(Icons.settings_ethernet),
                label: const Text('Configurar conexión'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _reintentando ? null : _reintentar,
                icon: _reintentando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
