import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llegue_mobile/core/copy/outing_copy.dart';
import 'package:llegue_mobile/features/family_circle/kid_offline_help_screen.dart';
import 'package:llegue_mobile/features/onboarding/permissions_notifications_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copy de salida especial según quién mira y quién la armó', () {
    expect(
      OutingCopy.specialOuting(
        viewerIsKid: false,
        viewerId: 'adult-1',
        kidName: 'Mateo',
        destination: 'Supermercado',
        creatorId: 'adult-1',
        creatorName: 'Enzo',
        viewerCreated: true,
      ),
      'Armaste una salida especial para Mateo a Supermercado',
    );
    expect(
      OutingCopy.specialOuting(
        viewerIsKid: false,
        viewerId: 'adult-2',
        kidName: 'Mateo',
        destination: 'Supermercado',
        creatorId: 'adult-1',
        creatorName: 'Enzo',
      ),
      'Enzo armó una salida especial para Mateo a Supermercado',
    );
    expect(
      OutingCopy.specialOuting(
        viewerIsKid: true,
        viewerId: 'kid-1',
        kidName: 'Mateo',
        destination: 'Supermercado',
        creatorId: 'adult-1',
        creatorName: 'Enzo',
      ),
      'Enzo te armó una salida especial a Supermercado',
    );
  });

  test('adulto nunca ve Te armaron', () {
    final rewritten = OutingCopy.rewrite(
      raw: 'Te armaron una salida especial a Supermercado',
      viewerIsKid: false,
      viewerId: 'adult-1',
      kidName: 'Mateo',
      creatorId: 'adult-1',
      creatorName: 'Enzo',
      viewerCreated: true,
    );
    expect(rewritten.toLowerCase().contains('te armaron'), isFalse);
    expect(rewritten, contains('Armaste una salida especial para Mateo'));
    expect(rewritten, contains('Supermercado'));
  });

  test('otro adulto con creador desconocido tampoco ve Te armaron', () {
    final rewritten = OutingCopy.rewrite(
      raw: 'Te armaron una salida especial a Supermercado',
      viewerIsKid: false,
      viewerId: 'adult-2',
      kidName: 'Mateo',
    );
    expect(rewritten.toLowerCase().contains('te armaron'), isFalse);
    expect(rewritten, 'Hay una salida especial para Mateo a Supermercado');
  });

  test('aviso de ubicación cortada se reconoce y arma payload', () {
    final members = [
      {
        'id': 'k1',
        'role': 'kid',
        'name': 'Mateo',
        'phone': '5491112345678',
      },
      {'id': 'a1', 'role': 'adult', 'name': 'Enzo'},
    ];
    expect(
      KidOfflineInfo.matches(
        title: 'Ubicación cortada',
        body: 'Mateo dejó de compartir ubicación',
      ),
      isTrue,
    );
    expect(
      KidOfflineInfo.matches(
        title: 'App cerrada',
        body: 'Mateo cerró la app Llegué',
      ),
      isTrue,
    );
    expect(
      KidOfflineInfo.matches(
        title: 'Llegué',
        body: 'Mateo llegó a Casa',
      ),
      isFalse,
    );
    final info = KidOfflineInfo.resolve(
      title: 'Ubicación cortada',
      body: 'Mateo dejó de compartir ubicación',
      members: members,
    );
    expect(info, isNotNull);
    expect(info!.kidName, 'Mateo');
    expect(info.kidPhone, '5491112345678');
    expect(info.toJson()['kind'], KidOfflineInfo.payloadKind);
    expect(
      KidOfflineInfo.fromJson(info.toJson())?.kidName,
      'Mateo',
    );
  });

  testWidgets('Avisos: recuadro glass compacto, sin vacío enorme', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PermissionsNotificationsScreen()),
    );
    expect(find.text('Avisos'), findsOneWidget);
    expect(find.text('Activar avisos'), findsOneWidget);
    expect(
      find.textContaining('Cuando el celular pregunte'),
      findsOneWidget,
    );
    expect(
      find.text('Sin esto, no vas a ver los avisos a tiempo.'),
      findsOneWidget,
    );
    final src =
        File('lib/features/onboarding/permissions_notifications_screen.dart')
            .readAsStringSync();
    expect(src.contains('mainAxisSize: MainAxisSize.min'), isTrue);
    expect(src.contains('const Spacer(),'), isTrue);
    expect(src.contains('\\n\\n'), isFalse);
    expect(src.contains('Expanded('), isFalse);
  });

  testWidgets('pantalla de ubicación cortada tiene CTA a WhatsApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KidOfflineHelpScreen(
          info: const KidOfflineInfo(
            kidName: 'Mateo',
            kidPhone: '5491112345678',
          ),
        ),
      ),
    );
    expect(find.text('Mateo dejó de compartir ubicación'), findsOneWidget);
    expect(find.text('Avisale a Mateo que abra Llegué'), findsOneWidget);
  });
}
