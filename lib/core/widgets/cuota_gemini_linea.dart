import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Línea compacta de cupo diario de Gemini: modelo, usadas hoy y barra.
///
/// El tope por modelo no lo publica Google en la API: solo aparece cuando el
/// error 429 lo informa. Por eso si [limite] es `null` se muestra solo el
/// contador, sin inventar un saldo.
class CuotaGeminiLinea extends StatelessWidget {
  const CuotaGeminiLinea({
    super.key,
    required this.modelo,
    required this.usadas,
    this.limite,
    this.reinicio,
    this.compacta = false,
  });

  final String modelo;
  final int usadas;

  /// Tope diario que Google reportó para este modelo, si ya se conoce.
  final int? limite;

  /// Instante local en que se reinicia el cupo (medianoche hora Pacífico).
  final DateTime? reinicio;

  /// Sin barra de progreso, para caber dentro del diálogo de identificación.
  final bool compacta;

  /// Avance 0..1 del cupo, o `null` si todavía no se conoce el tope.
  double? get _avance =>
      (limite == null || limite! <= 0) ? null : usadas / limite!;

  bool get _casiLleno => _avance != null && _avance! >= 0.8;

  bool get _lleno => _avance != null && _avance! >= 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    final colorAlerta = _lleno
        ? scheme.error
        : _casiLleno
            ? appColor(context, 'warning')
            : null;
    final colorIcono = colorAlerta ?? scheme.onSurfaceVariant;
    final colorBarra = colorAlerta ?? scheme.primary;

    final contador =
        limite == null ? '$usadas usadas hoy' : '$usadas de $limite';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              _lleno ? Icons.error_outline : Icons.speed,
              size: 16,
              color: colorIcono,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$modelo · $contador',
                style: texto.bodySmall?.copyWith(
                  color: colorAlerta ?? scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (!compacta) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _avance,
              minHeight: 6,
              color: colorBarra,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          _pie(),
          style: texto.labelSmall?.copyWith(color: colorIcono),
        ),
      ],
    );
  }

  String _pie() {
    if (_lleno) return 'Cupo diario agotado; la app prueba otros modelos sola.';
    final hora = reinicio == null ? null : _horaCorta(reinicio!);
    final base = hora == null
        ? 'Cupo diario del modelo (se reinicia a medianoche hora PT).'
        : 'Se reinicia a las $hora (hora de este dispositivo).';
    if (_casiLleno) return '$base ¡Queda poco cupo!';
    return base;
  }

  static String _horaCorta(DateTime momento) {
    String dd(int v) => v.toString().padLeft(2, '0');
    return '${dd(momento.hour)}:${dd(momento.minute)}';
  }
}
