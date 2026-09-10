import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'postgres_providers.dart';

/// Muestra un SnackBar amigable cuando PostgreSQL no esta configurado.
void showPostgresNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('PostgreSQL no configurado. Verifica la conexion.'),
      backgroundColor: Colors.orange,
      duration: Duration(seconds: 3),
    ),
  );
}

/// Provider auxiliar: retorna true si PostgreSQL esta disponible.
final postgresReadyProvider = Provider<bool>((ref) {
  return ref.watch(postgresServiceProvider) != null;
});