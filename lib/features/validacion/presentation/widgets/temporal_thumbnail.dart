import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/temporales_repository.dart';
import '../../data/validacion_providers.dart';

/// Miniatura de un temporal cargada bajo demanda (los metadatos del poll no
/// incluyen la imagen). Decodifica con `cacheWidth` para no renderizar fotos
/// completas en una miniatura.
class TemporalThumbnail extends ConsumerWidget {
  const TemporalThumbnail({super.key, required this.temporal, this.size = 48});

  final TemporalData temporal;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = temporal.id;
    if (id == null) {
      return Icon(Icons.image_not_supported_outlined,
          size: size >= 40 ? 28 : 24);
    }
    final repo = ref.watch(temporalesRepoProvider);
    return FutureBuilder<Uint8List?>(
      future: repo.getImagenTemporal(id),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Icon(Icons.image_not_supported_outlined,
              size: size >= 40 ? 28 : 24);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 160,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}