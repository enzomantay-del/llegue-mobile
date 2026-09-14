import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/invite_links.dart';
import 'core/state/app_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/family_circle/home_screen.dart';
import 'features/family_setup/create_family_screen.dart';
import 'features/family_setup/join_family_screen.dart';
import 'features/legal/terms_screen.dart';
import 'features/onboarding/keep_alive_onboarding_screen.dart';
import 'features/onboarding/permissions_blocked_screen.dart';
import 'features/onboarding/permissions_location_screen.dart';
import 'features/onboarding/permissions_notifications_screen.dart';
import 'features/onboarding/phone_login_screen.dart';
import 'features/onboarding/setup_checklist_screen.dart';
import 'features/onboarding/titular_onboarding_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/places/places_screen.dart';
import 'features/routines/routines_screen.dart';
import 'features/settings/alert_prefs_screen.dart';
import 'features/settings/help_screen.dart';
import 'features/settings/profile_screen.dart';
import 'features/settings/settings_hub_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  final app = AppController();
  await app.bootstrap();

  try {
    final links = AppLinks();
    final initial = await links.getInitialLink();
    final token = inviteTokenFromUri(initial);
    if (token != null && !app.hasFamily) {
      await app.setPendingInvite(token);
    }
  } catch (_) {}

  runApp(LlegueApp(controller: app));
}

class LlegueApp extends StatefulWidget {
  const LlegueApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<LlegueApp> createState() => _LlegueAppState();
}

class _LlegueAppState extends State<LlegueApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = AppLinks().uriLinkStream.listen((uri) async {
        final token = inviteTokenFromUri(uri);
        if (token == null) return;
        if (widget.controller.hasFamily) return;
        await widget.controller.setPendingInvite(token);
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          JoinFamilyScreen.route,
          (_) => false,
          arguments: token,
        );
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.onAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: MaterialApp(
        title: 'Llegué',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.brand(),
        navigatorKey: navigatorKey,
        initialRoute: widget.controller.startRoute,
        routes: {
          WelcomeScreen.route: (_) => const WelcomeScreen(),
          TitularOnboardingScreen.route: (_) => const TitularOnboardingScreen(),
          PhoneLoginScreen.route: (_) => const PhoneLoginScreen(),
          CreateFamilyScreen.route: (_) => const CreateFamilyScreen(),
          JoinFamilyScreen.route: (_) => const JoinFamilyScreen(),
          PermissionsLocationScreen.route: (_) =>
              const PermissionsLocationScreen(),
          PermissionsNotificationsScreen.route: (_) =>
              const PermissionsNotificationsScreen(),
          KeepAliveOnboardingScreen.route: (_) =>
              const KeepAliveOnboardingScreen(),
          PermissionsBlockedScreen.route: (_) =>
              const PermissionsBlockedScreen(),
          SetupChecklistScreen.route: (_) => const SetupChecklistScreen(),
          HomeScreen.route: (_) => const HomeScreen(),
          PlacesScreen.route: (_) => const PlacesScreen(),
          RoutinesScreen.route: (_) => const RoutinesScreen(),
          AlertPrefsScreen.route: (_) => const AlertPrefsScreen(),
          SettingsHubScreen.route: (_) => const SettingsHubScreen(),
          ProfileScreen.route: (_) => const ProfileScreen(),
          HelpScreen.route: (_) => const HelpScreen(),
          TermsScreen.route: (_) => const TermsScreen(),
        },
      ),
    );
  }
}
