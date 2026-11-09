import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/hardprepare_reply_dialog.dart';
import 'package:mithka/chat/hardprepare_reply_service.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const brief = 'Клиент спрашивает о пробном NUET.';
  const suggestion = 'Здравствуйте! Когда вам удобно пройти пробный NUET?';

  for (final (platform, simple) in [
    (TargetPlatform.macOS, false),
    (TargetPlatform.android, false),
    (TargetPlatform.android, true),
  ]) {
    testWidgets('opens from the composer on $platform, simple=$simple', (
      tester,
    ) async {
      final vm = ChatViewModel(
        chatId: 2,
        title: 'Client',
        markReadOnOpen: false,
      )..peerUserId = 2;
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(platform: platform, extensions: [AppColors.light]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                simpleMode: simple,
                quickRepliesEnabled: false,
                onStartCall: (_) {},
                onMessageSent: () =>
                    fail('A suggestion cannot send a message.'),
              ),
            ),
          ),
        ),
      );
      if (platform == TargetPlatform.macOS) {
        await tester.tap(
          find.byKey(const ValueKey('desktopComposerHardPrepareReply')),
        );
      } else {
        await tester.tap(
          simple
              ? find.byKey(const ValueKey('composerSimpleMoreButton'))
              : find.byWidgetPredicate(
                  (widget) =>
                      widget is AppIcon &&
                      widget.icon == HeroAppIcons.circlePlus,
                ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('HardPrepare'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Ответ HardPrepare'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Ответ HardPrepare'), findsNothing);
    });
  }

  for (final size in [const Size(360, 640), const Size(920, 650)]) {
    testWidgets('draft requires a separate insert action at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final response = Completer<http.Response>();
      var calls = 0;
      String? inserted;
      SharedPreferences.setMockInitialValues({});
      final settings = AiSettingsController(
        await SharedPreferences.getInstance(),
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
      );
      addTearDown(settings.dispose);
      await settings.saveServerProfile(
        name: 'Alem.ai',
        endpoint: alemQwenEndpoint,
        model: alemQwenModel,
        apiKey: 'fixture-key',
        contextWindowTokens: AiModelProfile.defaultContextWindowTokens,
      );
      final service = http.runWithClient(
        () => HardPrepareReplyService(settings: settings),
        () => MockClient((request) async {
          calls++;
          expect(request.url.toString(), alemQwenEndpoint);
          expect(request.headers['authorization'], 'Bearer fixture-key');
          expect(request.followRedirects, isFalse);
          final body = jsonDecode(utf8.decode(request.bodyBytes)) as Map;
          expect(body['model'], alemQwenModel);
          expect(body['messages'], [
            {'role': 'system', 'content': contains('HardPrepare')},
            {'role': 'user', 'content': brief},
          ]);
          expect(body.containsKey('tools'), isFalse);
          return response.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  inserted = await showHardPrepareReplyDialog(context, service);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подсказать'));
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), brief);
      await tester.pump();
      await tester.tap(find.text('Подсказать'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Модель готовит черновик…'), findsOneWidget);
      expect(inserted, isNull);

      response.complete(
        http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': suggestion},
                },
              ],
            }),
          ),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(suggestion), findsOneWidget);
      expect(inserted, isNull);
      await tester.tap(find.text('Вставить'));
      await tester.pumpAndSettle();
      expect(inserted, suggestion);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dialog stays dismissible above a compact phone keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 315);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [AppColors.dark]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHardPrepareReplyDialog(
                context,
                HardPrepareReplyService(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Закрыть').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ответ HardPrepare'), findsNothing);
  });
}
