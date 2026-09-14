import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/state/app_controller.dart';
import 'package:llegue_mobile/core/storage/session_store.dart';
import 'package:llegue_mobile/features/onboarding/keep_alive_onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('copy iOS vs Android', () {
    expect(
      KeepAliveOnboardingScreen.copyForPlatform(TargetPlatform.iOS),
      contains('selector de apps'),
    );
    expect(
      KeepAliveOnboardingScreen.copyForPlatform(TargetPlatform.android),
      contains('cerrás a la fuerza'),
    );
  });

  test('SharedPreferences guarda que ya vio la pantalla', () async {
    final store = SessionStore();
    expect(await store.keepAliveOnboardingSeen, isFalse);
    await store.setKeepAliveOnboardingSeen(true);
    expect(await store.keepAliveOnboardingSeen, isTrue);
    await store.clearSession();
    expect(await store.keepAliveOnboardingSeen, isTrue);
  });

  test('startRoute inserta el paso después de permisos y antes del Home', () {
    final app = AppController();
    app.api.accessToken = 't';
    app.user = {
      'id': 'k1',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1', 'name': 'Casa'};
    app.permissionsReady = true;
    app.keepAliveOnboardingSeen = false;

    expect(app.startRoute, KeepAliveOnboardingScreen.route);

    app.keepAliveOnboardingSeen = true;
    expect(app.startRoute, '/home');
  });

  testWidgets('pantalla: título, Entendido, sin skip', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final app = AppController();
    app.api.accessToken = 't';
    app.user = {
      'id': 'k1',
      'name': 'Mateo',
      'role': 'kid',
      'familyId': 'f1',
    };
    app.family = {'id': 'f1'};
    app.permissionsReady = true;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          home: const KeepAliveOnboardingScreen(),
          routes: {
            '/home': (_) => const Scaffold(body: Text('HOME')),
          },
        ),
      ),
    );

    expect(find.text('Para que Llegué avise de verdad'), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);
    expect(find.textContaining('cerrás a la fuerza'), findsOneWidget);
    expect(find.textContaining('Saltar'), findsNothing);
    expect(find.textContaining('Omitir'), findsNothing);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(app.keepAliveOnboardingSeen, isTrue);
    expect(find.text('HOME'), findsOneWidget);
  });

  test('salida especial no pide aviso familiar al crear el viaje', () {
    final home =
        File('lib/features/family_circle/home_screen.dart').readAsStringSync();
    expect(home.contains('forceNotify: false'), isTrue);
    expect(home.contains("okMsg: 'Salida armada'"), isTrue);
    expect(home.contains('Ya avisaste que saliste'), isFalse);
    final api = File('lib/core/api/api_client.dart').readAsStringSync();
    expect(
      api.contains("if (forceNotify != null) 'forceNotify': forceNotify"),
      isTrue,
    );
  });
}
