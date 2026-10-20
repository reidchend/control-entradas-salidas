import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clave y modelo del servicio de IA (Gemini) para identificar activos.
///
/// La clave vive en `flutter_secure_storage` (Keystore/Keychain en Android,
/// DPAPI en Windows), igual que la contraseña de la base: nunca en
/// `SharedPreferences` ni en el código.
class IaConfig {
  IaConfig({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Modelo multimodal por defecto (imagen + búsqueda de Google).
  ///
  /// 2.5 Flash ya no está disponible para proyectos nuevos; Google recomienda
  /// 3.8 Flash. Si la cuenta sí tiene 2.5, se puede cambiar en Ajustes → IA.
  static const modeloPorDefecto = 'gemini-3.8-flash';

  static const _kClave = 'ia_gemini_api_key';
  static const _kModelo = 'ia_gemini_modelo';

  Future<String?> leerClave() async {
    final valor = await _storage.read(key: _kClave);
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  Future<bool> hayClave() async => (await leerClave()) != null;

  Future<void> guardarClave(String clave) async {
    final texto = clave.trim();
    if (texto.isEmpty) {
      await borrarClave();
      return;
    }
    await _storage.write(key: _kClave, value: texto);
  }

  Future<void> borrarClave() => _storage.delete(key: _kClave);

  Future<String> leerModelo() async {
    final valor = (await _storage.read(key: _kModelo))?.trim() ?? '';
    return valor.isEmpty ? modeloPorDefecto : valor;
  }

  Future<void> guardarModelo(String modelo) async {
    final texto = modelo.trim();
    if (texto.isEmpty) {
      await _storage.delete(key: _kModelo);
      return;
    }
    await _storage.write(key: _kModelo, value: texto);
  }
}
