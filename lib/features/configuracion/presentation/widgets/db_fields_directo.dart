import 'package:flutter/material.dart';

/// Campos de conexión TCP directa a PostgreSQL.
///
/// Solo se usan si el equipo del cliente llega al puerto 5432: por Tailscale,
/// por red local o por VPN. La app abre un pool con el driver nativo, así que
/// cada query va sobre la conexión ya establecida.
class DbFieldsDirecto extends StatelessWidget {
  const DbFieldsDirecto({
    super.key,
    required this.hostCtrl,
    required this.puertoCtrl,
    required this.dbCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.ssl,
    required this.onSslChanged,
  });

  final TextEditingController hostCtrl;
  final TextEditingController puertoCtrl;
  final TextEditingController dbCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool ssl;
  final ValueChanged<bool> onSslChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        TextFormField(
          controller: hostCtrl,
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
                controller: dbCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base de datos',
                  hintText: 'control_entradas',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: puertoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Puerto',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final p = int.tryParse((v ?? '').trim());
                  if (p == null || p < 1 || p > 65535) return 'Inválido';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: userCtrl,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: ssl,
          onChanged: onSslChanged,
          title: const Text('Usar SSL', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            'Con Tailscale activalo: el tráfico ya va cifrado.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
