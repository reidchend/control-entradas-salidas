import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ia/gemini_cuota.dart';
import '../../../../core/widgets/cuota_gemini_linea.dart';

/// URL oficial del consumo de la clave en Google AI Studio (no hay
/// `url_launcher` en el proyecto, así que se muestra y se puede copiar).
const urlUsoIa = 'https://aistudio.google.com/usage';

/// Tarjeta de Ajustes → IA con el cupo diario de Gemini usado por este
/// dispositivo.
///
/// Google no publica cuántos intentos quedan: la app cuenta los propios y usa
/// el tope que Google informa en el error 429. El número es por dispositivo,
/// así que se rotula como tal y no como saldo exacto.
class IaCuotaCard extends StatefulWidget {
  const IaCuotaCard({super.key});

  @override
  State<IaCuotaCard> createState() => _IaCuotaCardState();
}

class _IaCuotaCardState extends State<IaCuotaCard> {
  GeminiCuota? _cuota;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cuota = await GeminiCuota.abrir();
    if (!mounted) return;
    setState(() => _cuota = cuota);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final cuota = _cuota;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: cuota == null
            ? const LinearProgressIndicator()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cupo de IA de hoy',
                          style: texto.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar',
                        icon: const Icon(Icons.refresh),
                        onPressed: _cargar,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contado desde este dispositivo. Si usás la misma clave en '
                    'otro equipo o en AI Studio, ese gasto no se cuenta acá.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._filas(cuota),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.copy, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          urlUsoIa,
                          style: texto.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar enlace',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(
                          const ClipboardData(text: urlUsoIa),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Ahí está el número exacto que ve Google.',
                    style: texto.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _filas(GeminiCuota cuota) {
    final usados = cuota.modelosUsados();
    if (usados.isEmpty) {
      return [
        Text(
          'Todavía no se identificó ningún artículo con IA hoy.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }
    final reinicio = cuota.proximoReinicio();
    return [
      for (final modelo in usados) ...[
        CuotaGeminiLinea(
          modelo: modelo,
          usadas: cuota.usadas(modelo),
          limite: cuota.limite(modelo),
          reinicio: reinicio,
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}
