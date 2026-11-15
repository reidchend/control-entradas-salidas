import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/updater/auto_update_checker.dart';
import '../../../configuracion/presentation/dialogs/db_config_dialog.dart';
import '../../data/pos_providers.dart';
import '../../data/pos_session.dart';
import 'widgets/personal_panel.dart';
import 'widgets/turnos_panel.dart';

/// Vista principal del POS (sin sesión): pestañas **Personal** (elegir usuario
/// y abrir/unirse al turno) y **Turnos** (turno abierto y cerrados).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Mantiene fresco el turno abierto mientras se está en el login: si otra
    // terminal lo abre o lo cierra, la tarjeta de Turnos y los usuarios
    // marcados como "en turno" se actualizan sin pull-to-refresh. Sin esto,
    // un participante expulsado (o que cambió de usuario) seguía viendo el
    // turno como abierto hasta refrescar a mano.
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      ref.invalidate(turnoAbiertoProvider);
      ref.invalidate(usuariosEnTurnoProvider);
    });
    // Aviso dejado por la revalidación de sesión (p. ej. el turno se cerró en
    // otra terminal). Se muestra una sola vez al llegar al login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final aviso = ref.read(avisoSesionProvider);
      if (aviso == null) return;
      ref.read(avisoSesionProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aviso)),
      );
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lycoris POS'),
        leading: Image.asset(
          'assets/icono_azul.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
        ),
        actions: [
          // Siempre disponible: con la base caída o sin configurar es la
          // única forma de llegar al panel de conexión sin pasar por el login.
          IconButton(
            tooltip: 'Configurar conexión',
            onPressed: () => showDbConfigDialog(context),
            icon: const Icon(Icons.settings_ethernet),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Personal'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Turnos'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              const PersonalPanel(),
              TurnosPanel(onIrAPersonal: () => _tabs.animateTo(0)),
            ],
          ),
          // Verificar actualizaciones antes del login (Windows/Android).
          const Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(top: 8, right: 8),
              child: AutoUpdateChecker(),
            ),
          ),
        ],
      ),
    );
  }
}
