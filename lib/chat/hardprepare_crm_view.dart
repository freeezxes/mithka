import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'hardprepare_crm_service.dart';

class HardPrepareCrmView extends StatefulWidget {
  const HardPrepareCrmView({
    super.key,
    required this.telegramId,
    required this.chatName,
  });

  final int telegramId;
  final String chatName;

  @override
  State<HardPrepareCrmView> createState() => _HardPrepareCrmViewState();
}

class _HardPrepareCrmViewState extends State<HardPrepareCrmView> {
  final _service = HardPrepareCrmService();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  Map<String, dynamic>? _contact;
  String? _error;
  bool _busy = false;
  bool _needsLogin = false;
  bool _needsCode = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool login = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on HardPrepareCrmException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.status == 401) {
          _needsLogin = true;
          _contact = null;
        }
        if (login || error.status != 401) _error = error.message;
        if (login) _needsCode = error.needsCode;
      });
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error = 'Не удалось открыть хранилище ключей устройства.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readContact() async {
    final contact = await _service.readContact(widget.telegramId);
    if (!mounted) return;
    setState(() {
      _needsLogin = false;
      _contact = contact;
    });
  }

  Future<void> _load() => _run(_readContact);

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Введите логин и пароль консоли.');
      return;
    }
    FocusScope.of(context).unfocus();
    await _run(() async {
      await _service.signIn(
        _user.text.trim(),
        _password.text,
        _code.text.trim(),
      );
      if (!mounted) return;
      _password.clear();
      _code.clear();
      setState(() => _needsLogin = false);
      await _readContact();
    }, login: true);
  }

  Future<void> _signOut() => _run(() async {
    await _service.signOut();
    if (!mounted) return;
    setState(() {
      _contact = null;
      _needsLogin = true;
    });
  });

  Widget _action(String label, AppIconData icon, VoidCallback onTap) => Tooltip(
    message: label,
    child: AppInteractiveSurface(
      semanticLabel: label,
      onTap: _busy ? null : onTap,
      child: SizedBox.square(
        dimension: AppMetric.hitTarget,
        child: Center(child: AppIcon(icon, size: AppIconSize.md)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    return SettingsPageScaffold(
      title: 'Карточка клиента',
      trailing: contact == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _action('Обновить карточку', HeroAppIcons.arrowsRotate, _load),
                _action(
                  'Выйти из CRM',
                  HeroAppIcons.rightFromBracket,
                  _signOut,
                ),
              ],
            ),
      child: SettingsListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_needsLogin) ...[
            Text(
              'Вход в HardPrepare',
              style: AppTextStyle.title(context.colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Используйте логин и пароль консоли HardPrepare.'),
            const SizedBox(height: AppSpacing.xxl),
            TextField(
              controller: _user,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Логин',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _password,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onSubmitted: _needsCode ? null : (_) => unawaited(_signIn()),
            ),
            if (_needsCode) ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Одноразовый код',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => unawaited(_signIn()),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppMetric.hitTarget),
              ),
              child: const Text('Войти в CRM'),
            ),
          ] else if (contact != null) ...[
            HardPrepareCrmCard(contact: contact, chatName: widget.chatName),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: LinearProgressIndicator(semanticsLabel: 'Загрузка CRM'),
            ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(liveRegion: true, child: Text(error)),
            if (!_needsLogin && !_busy)
              TextButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ],
      ),
    );
  }
}

class HardPrepareCrmCard extends StatelessWidget {
  const HardPrepareCrmCard({
    super.key,
    required this.contact,
    required this.chatName,
  });

  final Map<String, dynamic> contact;
  final String chatName;

  static const _platforms = {
    'nuet': 'NUET',
    'sat': 'SAT',
    'csca': 'CSCA',
    'ent': 'ЕНТ',
  };
  static const _sources = {
    'bot': 'Telegram-бот',
    'platform': 'Платформа',
    'mocks': 'Моки',
    'courses': 'Заявки',
    'trial': 'Пробник',
    'guides': 'Гайды',
    'repost': 'Акции',
    'marathon': 'Марафон',
    'reviews': 'Отзывы',
    'tobee': 'Архив Tobee',
  };
  static const _leadStatus = {
    'new': 'Новая',
    'contacted': 'Связались',
    'qualified': 'Квалифицирована',
    'paid': 'Оплачена',
    'enrolled': 'Записан',
    'done': 'Закрыта',
    'lost': 'Закрыта',
    'cancelled': 'Отменена',
  };
  static const _leadSources = {
    'site-b3': 'Сайт Batch 3',
    'bot-b3': 'Бот Batch 3',
    'telegram': 'Telegram',
    'bot': 'Telegram-бот',
    'site': 'Сайт',
    'website': 'Сайт',
  };
  static const _paymentStatus = {
    'paid': 'Оплачено',
    'pending': 'Ожидает оплаты',
    'creating': 'Счёт создаётся',
    'uncertain': 'Проверяется',
    'review': 'Требует проверки',
    'failed': 'Не оплачен',
    'refunded': 'Возврат',
  };

  static final _date = DateFormat('dd.MM.yyyy HH:mm');
  static final _money = NumberFormat.decimalPattern('ru');

  List<Map<String, dynamic>> _rows(String key) =>
      (contact[key] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

  String? _when(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final utc = DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z');
    return utc == null ? null : _date.format(utc.add(const Duration(hours: 5)));
  }

  String _details(Iterable<String?> values) =>
      values.whereType<String>().where((value) => value.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary = c.textPrimary.withValues(alpha: 0.82);
    SettingsRow contactRow(String title, [String? subtitle]) => SettingsRow(
      title: title,
      subtitle: subtitle,
      subtitleColor: secondary,
      subtitleMaxLines: 4,
      showChevron: false,
    );
    final status = contact['status'];
    final name = contact['display_name'] as String? ?? chatName;
    final registered = _when(contact['registered_at']);
    final bot = _when(contact['bot_last_at'] ?? contact['bot_first_at']);
    final platforms = _rows('platforms');
    final leads = _rows('leads');
    final payments = _rows('payments');
    final events = _rows('events');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          style: AppTextStyle.title(c.textPrimary).copyWith(
            fontSize: AppTextSize.largeDisplay,
            fontWeight: AppTextWeight.semibold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(switch (status) {
          'test_account' => 'Тестовый аккаунт HardPrepare',
          'unknown' => 'По этому Telegram ID пока нет связанных записей.',
          _ => 'Время событий по Алматы',
        }, style: AppTextStyle.footnote(secondary)),
        if (status == 'found') ...[
          if (platforms.isNotEmpty || bot != null || registered != null) ...[
            const SizedBox(height: AppSpacing.section),
            SettingsSection(
              title: 'Где был',
              headerColor: secondary,
              rows: [
                for (final row in platforms)
                  contactRow(
                    _platforms[row['studio']] ?? row['studio'].toString(),
                    _details([
                      if (_when(row['first_seen_at']) case final first?)
                        'Первый визит $first',
                      if (_when(row['last_seen_at']) case final last?)
                        'Последний $last',
                    ]),
                  ),
                if (bot != null)
                  contactRow('Telegram-бот', 'Последняя активность $bot'),
                if (registered != null)
                  contactRow('Аккаунт HardPrepare', 'Создан $registered'),
              ],
            ),
          ],
          if (leads.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            SettingsSection(
              title: 'Заявки',
              headerColor: secondary,
              rows: [
                for (final row in leads)
                  contactRow(
                    row['exam'] as String? ?? 'Заявка на обучение',
                    _details([
                      _leadStatus[row['status']] ?? row['status'] as String?,
                      _leadSources[row['source']],
                      _when(row['created_at']),
                    ]),
                  ),
              ],
            ),
          ],
          if (payments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            SettingsSection(
              title: 'Счета и оплаты',
              headerColor: secondary,
              rows: [
                for (final row in payments)
                  contactRow(
                    row['title'] as String? ?? 'Счёт',
                    _details([
                      if (row['amount_kzt'] case final num amount)
                        '${_money.format(amount)} ₸',
                      _paymentStatus[row['status']] ?? 'Статус уточняется',
                      _when(row['occurred_at']),
                    ]),
                  ),
              ],
            ),
          ],
          if (events.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            SettingsSection(
              title: 'Последние события',
              headerColor: secondary,
              rows: [
                for (final row in events)
                  contactRow(
                    row['message'] as String? ?? 'Действие на платформе',
                    _details([
                      _sources[row['service']],
                      _when(row['occurred_at']) ?? 'Дата неизвестна',
                    ]),
                  ),
              ],
            ),
            if (contact['event_count'] case final int total
                when total > events.length)
              SettingsNote(
                text: 'Показано ${events.length} из $total событий.',
              ),
          ],
        ],
      ],
    );
  }
}
