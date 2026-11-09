import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/hardprepare_crm_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens CRM from the TDLib webAppUrl and recovers after failure', (
    tester,
  ) async {
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'ru-RU';
    addTearDown(() => Intl.defaultLocale = previousLocale);
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);

    final launch = Completer<Map<String, dynamic>>();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getAuthorizationState' => {'@type': 'authorizationStateReady'},
          'getMe' => {'@type': 'user', 'id': 8819652775},
          'searchPublicChat' => {'@type': 'chat', 'id': 8691793920},
          'getMainWebApp' => await launch.future,
          _ => throw StateError('Unexpected TDLib request'),
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
    addTearDown(TdClient.shared.closeProxy);

    final token = List.filled(64, 'a').join();
    var contactRequests = 0;
    await http.runWithClient(
      () async {
        await tester.binding.setSurfaceSize(const Size(360, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: theme,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(extensions: [AppColors.dark]),
              home: const HardPrepareCrmView(
                accountSlot: 0,
                telegramId: 123456,
                chatName: 'Тестовый клиент',
              ),
            ),
          ),
        );
        expect(find.text('Загружаем карточку клиента…'), findsOneWidget);

        launch.complete({
          '@type': 'mainWebApp',
          'url': {
            '@type': 'webAppUrl',
            'url': 'https://hardprepare.com/courses#tgWebAppData=test-proof',
            'require_same_origin': true,
          },
        });
        await tester.pumpAndSettle();
        expect(find.text('Повторить'), findsOneWidget);

        await tester.tap(find.text('Повторить'));
        await tester.pumpAndSettle();
        expect(find.text('Где был'), findsOneWidget);
        expect(find.text('Первый визит 09.11.2026 12:00'), findsOneWidget);
        await tester.binding.setSurfaceSize(const Size(920, 850));
        await tester.pumpAndSettle();
        expect(find.text('Где был'), findsOneWidget);
        expect(find.text('Повторить'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(contactRequests, 2);
      },
      () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        switch (request.url.pathSegments.last) {
          case 'session':
            expect(body['init_data'], 'test-proof');
            expect(body['verifier'], matches(RegExp(r'^[a-f0-9]{64}$')));
            return http.Response(jsonEncode({'token': token}), 200);
          case 'contact':
            expect(request.headers['authorization'], 'Bearer $token');
            expect(body['telegram_id'], '123456');
            if (contactRequests++ == 0) return http.Response('{}', 503);
            return http.Response(
              jsonEncode({
                'status': 'found',
                'platforms': [
                  {'studio': 'nuet', 'first_seen_at': '2026-11-09 07:00:00'},
                ],
              }),
              200,
            );
          default:
            throw StateError('Unexpected CRM request');
        }
      }),
    );
  });
}
