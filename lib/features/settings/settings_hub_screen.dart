import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_background.dart';
import '../legal/terms_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'alert_prefs_screen.dart';
import 'help_screen.dart';
import 'profile_screen.dart';

/// Hub de cuenta: perfil, avisos, ayuda y salir.
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  static const route = '/settings';

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _versionLabel = 'Versión ${info.version} (${info.buildNumber})';
      });
    });
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la cuenta'),
        content: const Text(
          'Vas a cerrar sesión en este celular. '
          'Podés volver a entrar cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AppController>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      WelcomeScreen.route,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final roleLabel = app.isKid
        ? 'Hijo/a'
        : (app.user?['role'] == 'admin_adult' ? 'Titular' : 'Adulto/a');

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Cuenta')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: appGlassDecoration(radius: 18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.brand.withValues(alpha: 0.35),
                      child: Text(
                        () {
                          final n = app.displayName.trim();
                          return n.isEmpty ? '?' : n[0].toUpperCase();
                        }(),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.displayName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$roleLabel · Plan Gratis',
                            style: GoogleFonts.dmSans(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                            ),
                          ),
                          if (_versionLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _versionLabel,
                              style: GoogleFonts.dmSans(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _HubTile(
                icon: Icons.person_outline_rounded,
                title: 'Mi perfil',
                subtitle: 'Datos de la cuenta y de tu familia',
                onTap: () =>
                    Navigator.of(context).pushNamed(ProfileScreen.route),
              ),
              if (app.isAdult)
                _HubTile(
                  icon: Icons.notifications_outlined,
                  title: 'Qué avisos quiero recibir',
                  subtitle: 'Elegí qué te llega al celular',
                  onTap: () =>
                      Navigator.of(context).pushNamed(AlertPrefsScreen.route),
                ),
              _HubTile(
                icon: Icons.help_outline_rounded,
                title: 'Ayuda',
                subtitle: 'Preguntas frecuentes, probar alarma y soporte',
                onTap: () => Navigator.of(context).pushNamed(HelpScreen.route),
              ),
              _HubTile(
                icon: Icons.description_outlined,
                title: 'Bases y condiciones',
                subtitle: 'Términos de uso de Llegué',
                onTap: () => Navigator.of(context).pushNamed(TermsScreen.route),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Salir de la cuenta'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: appGlassDecoration(radius: 16),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        onTap: onTap,
      ),
    );
  }
}
