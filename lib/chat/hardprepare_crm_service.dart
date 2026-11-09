import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

class HardPrepareCrmException implements Exception {
  const HardPrepareCrmException(this.message, {this.status});

  final String message;
  final int? status;
}

class HardPrepareCrmService {
  HardPrepareCrmService(this.accountSlot);

  static const supportUserId = 8819652775;
  static const _botId = 8691793920;
  static const accountRequired = HardPrepareCrmException(
    'Откройте карточку из аккаунта @hard_prep_support.',
  );
  static ({int clientId, String token})? _session;

  final int accountSlot;
  final _td = TdClient.shared;

  Future<Map<String, dynamic>> readContact(int telegramId) async {
    final clientId = _td.activeClientId;
    _checkAccount(clientId);
    try {
      final state = await _query({'@type': 'getAuthorizationState'}, clientId);
      if (state.type != 'authorizationStateReady') throw accountRequired;
      final me = await _query({'@type': 'getMe'}, clientId);
      if (me.int64('id') != supportUserId) throw accountRequired;
      var session = _session;
      if (session?.clientId != clientId) session = null;
      if (session != null) {
        try {
          return await _read(telegramId, clientId, session.token);
        } on HardPrepareCrmException catch (error) {
          if (error.status != 401) rethrow;
          if (_session == session) _session = null;
        }
      }
      final token = await _signIn(clientId);
      _session = (clientId: clientId, token: token);
      return await _read(telegramId, clientId, token);
    } on TdError {
      throw const HardPrepareCrmException(
        'Telegram не подтвердил вход. Попробуйте снова.',
      );
    } on TimeoutException {
      throw const HardPrepareCrmException(
        'Telegram не ответил. Попробуйте снова.',
      );
    } on StateError {
      throw accountRequired;
    }
  }

  void _checkAccount(int clientId) {
    if (clientId == 0 ||
        _td.activeSlot != accountSlot ||
        _td.activeClientId != clientId) {
      throw accountRequired;
    }
  }

  Future<Map<String, dynamic>> _query(
    Map<String, dynamic> request,
    int clientId,
  ) async {
    _checkAccount(clientId);
    final result = await _td.queryForSlot(
      request,
      accountSlot,
      timeout: const Duration(seconds: 12),
    );
    _checkAccount(clientId);
    return result;
  }

  Future<String> _signIn(int clientId) async {
    final random = Random.secure();
    final verifier = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final challenge = sha256.convert(utf8.encode(verifier)).toString();
    // Resolve the bot so TDLib has its input peer on a fresh installation.
    final bot = await _query({
      '@type': 'searchPublicChat',
      'username': 'hard_prep_bot',
    }, clientId);
    if (bot.int64('id') != _botId) throw accountRequired;
    final app = await _query({
      '@type': 'getMainWebApp',
      'chat_id': 0,
      'bot_user_id': _botId,
      'start_parameter': 'hp_inbox_$challenge',
      'parameters': {
        '@type': 'webAppOpenParameters',
        'theme': null,
        'application_name': 'android',
        'mode': {'@type': 'webAppOpenModeFullSize'},
      },
    }, clientId);
    // Current TDLib wraps the URL in webAppUrl. Older builds returned a string.
    final url = switch (app['url']) {
      {'url': final String url} => url,
      final String url => url,
      _ => '',
    };
    final uri = Uri.tryParse(url);
    String? initData;
    if (uri != null && uri.scheme == 'https' && uri.host == 'hardprepare.com') {
      try {
        initData = Uri.splitQueryString(uri.fragment)['tgWebAppData'];
      } on FormatException {
        throw const HardPrepareCrmException(
          'Telegram вернул неверную ссылку входа.',
        );
      }
    }
    if (initData == null || initData.isEmpty) {
      throw const HardPrepareCrmException('Telegram не подтвердил вход.');
    }
    final result = await _request(
      'session',
      body: {'init_data': initData, 'verifier': verifier},
    );
    _checkAccount(clientId);
    final token = result['token'];
    if (token is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const HardPrepareCrmException('Сервер вернул неверную сессию.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _read(
    int telegramId,
    int clientId,
    String token,
  ) async {
    _checkAccount(clientId);
    final contact = await _request(
      'contact',
      token: token,
      body: {'telegram_id': telegramId.toString()},
    );
    _checkAccount(clientId);
    return contact;
  }

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    String? token,
    required Map<String, String> body,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.https('hardprepare.com', '/api/console/inbox/$endpoint'),
      )..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      request.headers['User-Agent'] = 'HardPrepare Inbox';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
      final Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        data = decoded is Map<String, dynamic> ? decoded : {};
      } on FormatException {
        throw const HardPrepareCrmException('Сервер CRM временно недоступен.');
      }
      if (response.statusCode == 200 && data.isNotEmpty) return data;
      throw HardPrepareCrmException(switch (response.statusCode) {
        401 => 'Не удалось подтвердить вход через Telegram.',
        429 => 'Слишком много попыток. Попробуйте позже.',
        _ => 'Не удалось получить данные CRM. Попробуйте снова.',
      }, status: response.statusCode);
    } on TimeoutException {
      throw const HardPrepareCrmException('CRM не ответила. Попробуйте снова.');
    } on http.ClientException {
      throw const HardPrepareCrmException('Проверьте подключение к интернету.');
    } finally {
      client.close();
    }
  }
}
