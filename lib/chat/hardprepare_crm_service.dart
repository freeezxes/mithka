import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class HardPrepareCrmException implements Exception {
  const HardPrepareCrmException(
    this.message, {
    this.status,
    this.needsCode = false,
  });

  final String message;
  final int? status;
  final bool needsCode;
}

class HardPrepareCrmService {
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'hardprepare.inbox.crm',
      usesDataProtectionKeychain: false,
    ),
  );
  static const _sessionKey = 'hardprepare.inbox.crm.session';
  static String? _session;

  Future<String?> _readSession() async {
    if (_session != null) return _session;
    return _session = await _storage.read(key: _sessionKey);
  }

  Future<void> signIn(String username, String password, String code) async {
    final result = await _request(
      'POST',
      'session',
      body: {
        'username': username,
        'password': password,
        if (code.isNotEmpty) 'totp': code,
      },
    );
    final token = result['token'];
    if (token is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const HardPrepareCrmException('Сервер вернул неверную сессию.');
    }
    await _storage.write(key: _sessionKey, value: token);
    _session = token;
  }

  Future<Map<String, dynamic>> readContact(int telegramId) async {
    final token = await _readSession();
    if (token == null) {
      throw const HardPrepareCrmException('Войдите в CRM.', status: 401);
    }
    try {
      return await _request(
        'POST',
        'contact',
        token: token,
        body: {'telegram_id': telegramId.toString()},
      );
    } on HardPrepareCrmException catch (error) {
      if (error.status == 401 && _session == token) await _clearSession();
      rethrow;
    }
  }

  Future<void> signOut() async {
    final token = await _readSession();
    if (token == null) return;
    try {
      await _request('DELETE', 'session', token: token);
    } on HardPrepareCrmException catch (error) {
      if (error.status != 401) rethrow;
    }
    if (_session == token) await _clearSession();
  }

  Future<void> _clearSession() async {
    _session = null;
    await _storage.delete(key: _sessionKey);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    String? token,
    Map<String, String>? body,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request(
        method,
        Uri.https('hardprepare.com', '/api/console/inbox/$endpoint'),
      )..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      request.headers['User-Agent'] = 'HardPrepare Inbox';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.bodyBytes = utf8.encode(jsonEncode(body));
      }
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
      final login = endpoint == 'session' && method == 'POST';
      throw HardPrepareCrmException(
        switch (response.statusCode) {
          401 when login =>
            data['totp_required'] == true
                ? 'Проверьте логин, пароль и одноразовый код.'
                : 'Проверьте логин и пароль консоли.',
          401 => 'Сессия истекла. Войдите снова.',
          429 => 'Слишком много попыток. Повторите вход позже.',
          _ => 'Не удалось получить данные CRM. Попробуйте снова.',
        },
        status: response.statusCode,
        needsCode: data['totp_required'] == true,
      );
    } on TimeoutException {
      throw const HardPrepareCrmException('CRM не ответила. Попробуйте снова.');
    } on http.ClientException {
      throw const HardPrepareCrmException('Проверьте подключение к интернету.');
    } finally {
      client.close();
    }
  }
}
