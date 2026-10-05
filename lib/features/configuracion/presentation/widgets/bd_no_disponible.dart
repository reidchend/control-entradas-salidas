import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/db_config.dart';
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
    // Invalida el pool, que es dependencia del provider verificado: se rehacen
    // la sesión y el chequeo de salud. Refrescar la URL viene incluido, porque
    // `postgresPoolProvider` arranca con `forzarProxy: true`; si el túnel rotó,
    // el reintento toma la URL nueva sin que haya que tocar nada.
    ref.invalidate(postgresPoolProvider);
    try {
      // Se espera al verificado y no al pool: si no, el indicador dejaría de
      // girar antes de que el servidor haya contestado, que es justo lo que el
      // usuario está esperando ver.
      await ref.read(sesionVerificadaProvider.future);
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

    // Hay token guardado pero la URL no se pudo determinar: la app no está
    // "sin configurar", está configurada a medias. El título y el texto
    // apuntaban a "configurala una sola vez" en los dos casos, y eso mandaba a
    // reconfigurar un equipo que ya tenía el token puesto.
    final faltaUrl = error is DbNotConfiguredError &&
        error.motivo == MotivoSinConfigurar.urlNoDeterminada;
    final esSinConfigurar = estado == EstadoBd.noConfigurada && !faltaUrl;

    final titulo = switch ((esSinConfigurar, faltaUrl)) {
      (true, _) => 'Base de datos sin configurar',
      (_, true) => 'No se pudo obtener la dirección del servidor',
      _ => 'No se pudo conectar con la base de datos',
    };
    final mensaje = switch ((esSinConfigurar, faltaUrl)) {
      (true, _) =>
        'Esta app necesita saber a qué servidor conectarse antes de poder '
            'iniciar sesión. Es un paso que se hace una sola vez por equipo.',
      (_, true) =>
        'El token ya está escrito en este equipo, lo que falla es leer la '
            'dirección del servidor. El detalle dice por qué. Si preferís, '
            'podés escribir la URL a mano y la app deja de depender de esa '
            'lectura.',
      _ =>
        'La configuración está cargada, pero el servidor no respondió. '
            'Revisá que la PC servidor esté encendida y que la URL y el token '
            'siguan vigentes.',
    };

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
                esSinConfigurar || faltaUrl
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
              // El detalle se muestra siempre que exista. Estaba atado a `!esSinConfigurar`,
              // y justo el mensaje que explicaba el problema real ("no se pudo
              // determinar la URL") llegaba con `noConfigurada`: nunca se veía.
              if (error != null) ...[
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
