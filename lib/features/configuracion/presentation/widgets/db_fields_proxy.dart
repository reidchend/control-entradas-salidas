import 'package:flutter/material.dart';

/// Campos de conexión por proxy HTTP.
///
/// Es la vía recomendada para Windows y Android: la app habla HTTPS contra el
/// servidor, que habla con PostgreSQL. No requiere abrir el 5432 ni instalar
/// Tailscale en el equipo del cliente.
class DbFieldsProxy extends StatelessWidget {
  const DbFieldsProxy({
    super.key,
    required this.urlCtrl,
    required this.tokenCtrl,
    this.buscando = false,
    this.urlEditable = false,
    this.onBuscarUrl,
    this.onEditarUrl,
    this.onUsarUrlAutomatica,
  });

  final TextEditingController urlCtrl;
  final TextEditingController tokenCtrl;

  /// Estado de la búsqueda automática de la URL.
  final bool buscando;

  /// Permite escribir la URL a mano.
  ///
  /// Viene en `false`: la URL se descubre sola y lo único que el usuario tiene
  /// que escribir es el token. Se habilita a mano solo si la búsqueda falla.
  final bool urlEditable;

  /// Busca la URL publicada por el servidor. Si es `null`, no se muestra el
  /// botón (por ejemplo en web, donde la URL no es configurable).
  final VoidCallback? onBuscarUrl;

  /// Pasa el campo a editable.
  final VoidCallback? onEditarUrl;

  /// Vuelve al modo automático, descartando lo escrito a mano.
  final VoidCallback? onUsarUrlAutomatica;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urlVacia = urlCtrl.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: urlCtrl,
          autocorrect: false,
          readOnly: !urlEditable,
          keyboardType: TextInputType.url,
          style: urlEditable
              ? null
              : TextStyle(color: scheme.onSurface, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'URL del servidor',
            hintText: urlEditable
                ? 'https://api.tudominio.cl'
                : urlVacia
                    ? 'No se pudo obtener del servidor'
                    : null,
            helperText: urlEditable
                ? 'Sin /proxy-sql: se agrega sola.'
                : 'Detectada automáticamente. No hace falta escribirla.',
            helperStyle: TextStyle(
              fontSize: 11.5,
              color: urlVacia && !urlEditable ? scheme.error : null,
            ),
            border: const OutlineInputBorder(),
            suffixIcon: urlEditable || onBuscarUrl == null
                ? null
                : IconButton(
                    tooltip: 'Buscar la URL del servidor',
                    onPressed: buscando ? null : onBuscarUrl,
                    icon: buscando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore),
                  ),
          ),
          validator: (v) {
            final raw = (v ?? '').trim();
            if (raw.isEmpty) {
              return urlEditable
                  ? 'Requerido'
                  : 'No se pudo obtener la URL del servidor. Usá el botón de '
                      'abajo para escribirla a mano.';
            }
            final uri = Uri.tryParse(raw);
            if (uri == null ||
                !uri.hasScheme ||
                !uri.hasAuthority ||
                !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
              return 'Debe empezar con http:// o https://';
            }
            return null;
          },
        ),
        if (onEditarUrl != null || onUsarUrlAutomatica != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: urlEditable ? onUsarUrlAutomatica : onEditarUrl,
              icon: Icon(
                urlEditable ? Icons.auto_fix_high : Icons.edit_outlined,
                size: 16,
              ),
              label: Text(
                urlEditable
                    ? 'Usar la URL automática'
                    : 'Escribir la URL a mano',
                style: const TextStyle(fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextFormField(
          controller: tokenCtrl,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Token del proxy',
            helperText: 'El mismo PROXY_SQL_TOKEN del servidor.',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Requerido' : null,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El token da acceso a la base completa para quien lo tenga. '
                  'Cambialo si el equipo queda fuera de tu control.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
