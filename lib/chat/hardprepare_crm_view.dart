import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import 'hardprepare_crm_service.dart';

class HardPrepareCrmView extends StatefulWidget {
  const HardPrepareCrmView({
    super.key,
    required this.accountSlot,
    required this.telegramId,
    required this.chatName,
  });

  final int accountSlot;
  final int telegramId;
  final String chatName;

  @override
  State<HardPrepareCrmView> createState() => _HardPrepareCrmViewState();
}

class _HardPrepareCrmViewState extends State<HardPrepareCrmView> {
  late final _service = HardPrepareCrmService(widget.accountSlot);
  StreamSubscription<int>? _accountChanges;
  Map<String, dynamic>? _contact;
  String? _error;
  bool _busy = false;
  int _historyOffset = 0;
  bool _loadingHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _accountChanges = TdClient.shared.subscribeActiveSlotChanges().listen((
      slot,
    ) {
      if (slot == widget.accountSlot || !mounted) return;
      setState(() {
        _contact = null;
        _error = HardPrepareCrmService.accountRequired.message;
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_accountChanges?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final contact = await _service.readContact(widget.telegramId);
      if (mounted) {
        setState(() {
          _contact = contact;
          _historyOffset = _crmRows(contact['events']).length;
          _historyError = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (error is! HardPrepareCrmException) {
        debugPrint('CRM contact load failed: ${error.runtimeType}');
      }
      setState(() {
        _contact = null;
        _error = error is HardPrepareCrmException
            ? error.message
            : 'Не удалось загрузить карточку клиента.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMoreHistory() async {
    final contact = _contact;
    if (_loadingHistory || _busy || contact == null) return;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final page = await _service.readHistory(
        widget.telegramId,
        _historyOffset,
      );
      if (!mounted || !identical(_contact, contact)) return;
      final rows = _crmRows(page['events']);
      final current = _crmRows(contact['events']);
      final known = current.map((event) => event['id']).toSet();
      setState(() {
        _historyOffset = rows.isEmpty
            ? (page['event_count'] as int? ?? _historyOffset)
            : _historyOffset + rows.length;
        _contact = {
          ...contact,
          'event_count': page['event_count'],
          'events': [
            ...current,
            ...rows.where((event) => known.add(event['id'])),
          ],
        };
      });
    } catch (error) {
      if (mounted && identical(_contact, contact)) {
        setState(
          () => _historyError = error is HardPrepareCrmException
              ? error.message
              : 'Не удалось загрузить предыдущие события.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

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
          : _action('Обновить карточку', HeroAppIcons.arrowsRotate, _load),
      constrainContent: contact == null,
      child: contact != null
          ? HardPrepareCrmCard(
              contact: contact,
              chatName: widget.chatName,
              telegramId: widget.telegramId,
              refreshing: _busy,
              loadingHistory: _loadingHistory,
              historyError: _historyError,
              onLoadMore: _historyOffset < (contact['event_count'] as int? ?? 0)
                  ? _loadMoreHistory
                  : null,
            )
          : SettingsListView(
              children: [
                if (_busy || _error != null) ...[
                  Text(
                    widget.chatName,
                    style: AppTextStyle.title(context.colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _busy ? 'Загружаем карточку клиента…' : _error!,
                      style: AppTextStyle.body(context.colors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_busy)
                    const LinearProgressIndicator()
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

List<Map<String, dynamic>> _crmRows(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

class HardPrepareCrmCard extends StatelessWidget {
  const HardPrepareCrmCard({
    super.key,
    required this.contact,
    required this.chatName,
    required this.telegramId,
    required this.refreshing,
    required this.loadingHistory,
    required this.historyError,
    required this.onLoadMore,
  });

  final Map<String, dynamic> contact;
  final String chatName;
  final int telegramId;
  final bool refreshing;
  final bool loadingHistory;
  final String? historyError;
  final VoidCallback? onLoadMore;

  static const _platforms = {
    'nuet': 'NUET',
    'sat': 'SAT',
    'csca': 'CSCA',
    'ent': 'ЕНТ',
  };
  static const _sources = {
    'bot': 'Telegram-бот',
    'platform': 'Платформа',
    'mocks': 'Пробные экзамены',
    'courses': 'Заявки',
    'trial': 'Пробник',
    'guides': 'Гайды',
    'repost': 'Акции',
    'marathon': 'Марафон',
    'reviews': 'Отзывы',
    'tobee': 'Архив Tobee',
  };
  static const _leadStatus = {
    'new': 'Новая заявка',
    'contacted': 'Связались',
    'qualified': 'Квалифицирована',
    'paid': 'Оплачена',
    'enrolled': 'Записан',
    'waitlist': 'Лист ожидания',
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
    'cancelled': 'Отменён',
    'expired': 'Истёк',
  };

  static final _date = DateFormat('dd.MM.yyyy HH:mm', 'en_US');
  static final _day = DateFormat('dd.MM.yyyy', 'en_US');
  static final _time = DateFormat('HH:mm', 'en_US');
  static final _money = NumberFormat.decimalPattern('ru');

  DateTime? _localTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final iso = value.replaceFirst(' ', 'T');
    final hasZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(iso);
    return DateTime.tryParse(
      hasZone ? iso : '${iso}Z',
    )?.toUtc().add(const Duration(hours: 5));
  }

  String? _when(Object? value) {
    final local = _localTime(value);
    return local == null ? null : _date.format(local);
  }

  String? _text(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  String? _amount(Object? value) =>
      value is num ? '${_money.format(value)} тг' : null;

  String? _details(Iterable<String?> values) {
    final joined = values
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .join(' · ');
    return joined.isEmpty ? null : joined;
  }

  SettingsRow _row(BuildContext context, String title, [String? subtitle]) =>
      SettingsRow(
        title: title,
        subtitle: subtitle,
        subtitleMaxLines: 5,
        subtitleColor: context.colors.textPrimary.withValues(alpha: 0.88),
        showChevron: false,
      );

  Widget _section(BuildContext context, String title, List<SettingsRow> rows) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        child: SettingsSection(
          title: title,
          headerColor: context.colors.textPrimary.withValues(alpha: 0.88),
          rows: rows,
        ),
      );

  Widget _empty(BuildContext context, String text) =>
      Text(text, style: AppTextStyle.body(context.colors.textPrimary));

  String _leadTitle(Map<String, dynamic> row) =>
      _text(row['exam']) ?? 'Заявка на обучение';

  String? _leadLabel(Map<String, dynamic> row) =>
      _leadStatus[row['status']] ?? _text(row['status']);

  Widget _overview(BuildContext context) {
    final platforms = _crmRows(contact['platforms']);
    final leads = _crmRows(contact['leads']);
    final access = _crmRows(
      contact['access'],
    ).where((item) => item['active'] == 1).toList();
    final totals = contact['payment_totals'];
    final paid = totals is Map && totals['invoice_count'] != 0
        ? _amount(totals['paid_kzt'])
        : null;
    final bot = _when(contact['bot_last_at'] ?? contact['bot_first_at']);
    final registered = _when(contact['registered_at']);
    final events = _crmRows(contact['events']);
    return SettingsListView(
      children: [
        if (leads.isNotEmpty || access.isNotEmpty || paid != null)
          _section(context, 'Статус клиента', [
            if (leads.firstOrNull case final lead?)
              _row(
                context,
                _leadTitle(lead),
                _details([_leadLabel(lead), _when(lead['created_at'])]),
              ),
            for (final item in access)
              _row(
                context,
                _text(item['title']) ?? 'Доступ',
                _when(item['ends_at']) == null
                    ? 'Доступ активен'
                    : 'Активен до ${_when(item['ends_at'])}',
              ),
            if (paid != null) _row(context, 'Оплачено всего', paid),
          ]),
        if (platforms.isNotEmpty || bot != null || registered != null)
          _section(context, 'Где был', [
            for (final row in platforms)
              _row(
                context,
                _platforms[row['studio']] ?? row['studio'].toString(),
                _details([
                  if (_when(row['first_seen_at']) case final first?)
                    'Первый визит $first',
                  if (_when(row['last_seen_at']) case final last?)
                    'Последний визит $last',
                  if (row['active_days'] case final int days when days > 0)
                    'Дней с визитами: $days',
                ]),
              ),
            if (bot != null)
              _row(context, 'Telegram-бот', 'Последняя активность $bot'),
            if (registered != null)
              _row(context, 'Аккаунт HardPrepare', 'Создан $registered'),
          ])
        else
          _empty(context, 'Подтверждённых посещений платформ пока нет.'),
        if (events.isNotEmpty)
          _section(context, 'Недавние события', [
            for (final event in events.take(3))
              _row(
                context,
                _text(event['message']) ?? 'Действие',
                _when(event['occurred_at']),
              ),
          ]),
      ],
    );
  }

  Widget _study(BuildContext context) {
    final study = contact['study'];
    if (study is! Map) {
      return SettingsListView(
        children: [
          _empty(context, 'Учебный профиль ещё не связан с этим Telegram.'),
        ],
      );
    }
    final results = _crmRows(study['results']);
    final solved = study['solved'];
    final correct = study['correct'];
    final studio = contact['studio_learning'];
    final totals = studio is Map ? studio['totals'] : null;
    final days = studio is Map
        ? _crmRows(studio['days'])
        : const <Map<String, dynamic>>[];
    return SettingsListView(
      children: [
        if (totals is Map) ...[
          _section(context, 'Studio за 30 дней', [
            _row(context, 'Ответы в банке', '${totals['bank_answers']}'),
            if (totals['checked'] case final int checked when checked > 0)
              _row(
                context,
                'Верные ответы',
                '${totals['correct']} из $checked проверенных',
              ),
            _row(context, 'Ответы в моках', '${totals['mock_answers']}'),
            _row(
              context,
              'Пробные экзамены',
              'Начато ${totals['starts']} · завершено ${totals['completions']}',
            ),
          ]),
          if (days.isNotEmpty)
            _section(context, 'Дни занятий в Studio', [
              for (final day in days)
                _row(
                  context,
                  _text(day['day']) ?? 'Дата неизвестна',
                  _details([
                    if (day['bank_answers'] != 0)
                      'Ответов в банке: ${day['bank_answers']}',
                    if (day['mock_answers'] != 0)
                      'Ответов в моках: ${day['mock_answers']}',
                    if (day['starts'] != 0) 'Моков начато: ${day['starts']}',
                    if (day['completions'] != 0)
                      'Моков завершено: ${day['completions']}',
                  ]),
                ),
            ]),
        ] else if (studio is Map && studio['status'] == 'unavailable')
          const SettingsNote(
            text: 'Активность Studio временно недоступна. Обновите карточку.',
          ),
        if (solved is num && solved > 0 || _text(study['target']) != null)
          _section(context, 'Практика HardPrepare', [
            if (_text(study['target']) case final target?)
              _row(context, 'Направление', target),
            if (solved is num) _row(context, 'Решено задач', '$solved'),
            if (correct is num && solved is num && solved > 0)
              _row(context, 'Верных ответов', '$correct из $solved'),
            if (study['streak'] case final int streak when streak > 0)
              _row(context, 'Серия занятий', 'Дней подряд: $streak'),
          ]),
        if (results.isEmpty)
          _empty(context, 'Завершённых работ пока нет.')
        else
          _section(context, 'Последние результаты', [
            for (final result in results)
              _row(
                context,
                _text(result['title']) ?? 'Работа',
                _details([
                  if (result['score'] != null && result['total'] != null)
                    '${result['score']} из ${result['total']}',
                  if (result['percentage'] case final num percent)
                    '${percent.toStringAsFixed(1)}%',
                  _when(result['completed_at']),
                ]),
              ),
          ]),
      ],
    );
  }

  Widget _orders(BuildContext context) {
    final leads = _crmRows(contact['leads']);
    final access = _crmRows(contact['access']);
    final payments = _crmRows(contact['payments']);
    final totals = contact['payment_totals'];
    return SettingsListView(
      children: [
        if (leads.isEmpty && access.isEmpty && payments.isEmpty)
          _empty(context, 'Связанных заявок, доступов и счетов пока нет.'),
        if (leads.isNotEmpty)
          _section(context, 'Заявки', [
            for (final row in leads)
              _row(
                context,
                _leadTitle(row),
                [
                  _details([
                    _leadLabel(row),
                    _text(row['batch']),
                    _text(row['plan']),
                  ]),
                  _details([
                    _leadSources[row['source']] ?? _text(row['source']),
                    _when(row['created_at']),
                  ]),
                  _details([
                    if (_text(row['grade']) case final grade?) 'Класс $grade',
                    _text(row['study_lang']),
                    _text(row['schedule']),
                    if (row['trial_score'] != null)
                      'Пробник: ${row['trial_score']}',
                  ]),
                ].whereType<String>().join('\n'),
              ),
          ]),
        if (access.isNotEmpty)
          _section(context, 'Доступы', [
            for (final row in access)
              _row(
                context,
                _text(row['title']) ?? 'Доступ',
                _details([
                  row['active'] == 1 ? 'Активен' : 'Завершён',
                  if (_when(row['starts_at']) case final start?) 'С $start',
                  if (_when(row['ends_at']) case final end?) 'До $end',
                ]),
              ),
          ]),
        if (payments.isNotEmpty)
          _section(context, 'Счета и оплаты', [
            if (totals is Map)
              _row(
                context,
                'Оплачено всего',
                _details([
                  _amount(totals['paid_kzt']),
                  if (totals['paid_count'] case final int paid)
                    'Оплачено счетов: $paid',
                ]),
              ),
            for (final row in payments)
              _row(
                context,
                _text(row['title']) ?? 'Счёт',
                _details([
                  _amount(row['amount_kzt']),
                  _paymentStatus[row['status']] ?? 'Статус уточняется',
                  _when(
                    row['paid_at'] ?? row['created_at'] ?? row['occurred_at'],
                  ),
                ]),
              ),
          ]),
        if (totals is Map &&
            totals['invoice_count'] is int &&
            totals['invoice_count'] > payments.length)
          SettingsNote(
            text:
                'Показано ${payments.length} из ${totals['invoice_count']} счетов.',
          ),
      ],
    );
  }

  Widget _history(BuildContext context) {
    final events = _crmRows(contact['events']);
    if (events.isEmpty) {
      return SettingsListView(
        children: [_empty(context, 'В истории пока нет связанных событий.')],
      );
    }
    final days = <String, List<SettingsRow>>{};
    for (final event in events) {
      final date = _localTime(event['occurred_at']);
      final day = date == null ? 'Дата неизвестна' : _day.format(date);
      (days[day] ??= []).add(
        _row(
          context,
          _text(event['message']) ?? 'Действие',
          _details([
            if (date != null) _time.format(date),
            _sources[event['service']],
            if (event['historical'] == true) 'Из архива',
          ]),
        ),
      );
    }
    return SettingsListView(
      children: [
        if (contact['event_count'] case final int total)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: SettingsNote(
              text:
                  'Показано ${events.length} из $total событий. Время по Алматы.',
            ),
          ),
        for (final entry in days.entries)
          _section(context, entry.key, entry.value),
        if (historyError != null)
          Semantics(liveRegion: true, child: Text(historyError!)),
        if (onLoadMore != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: refreshing || loadingHistory ? null : onLoadMore,
              child: Text(
                loadingHistory ? 'Загружаем…' : 'Показать более ранние события',
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = contact['status'];
    final username = _text(
      contact['username'],
    )?.replaceFirst(RegExp(r'^@'), '');
    final lastSeen = _when(contact['last_active_at']);
    final name = _text(contact['display_name']) ?? chatName;
    final phone = _text(contact['phone']);
    final identity = _details([
      if (username != null) '@$username',
      'Telegram ID $telegramId',
      phone,
    ])!;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: AppTextStyle.title(
              c.textPrimary,
            ).copyWith(fontSize: AppTextSize.largeDisplay),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(identity, style: AppTextStyle.callout(c.textPrimary)),
          if (lastSeen != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Последняя активность $lastSeen',
              style: AppTextStyle.footnote(c.textSecondary),
            ),
          ],
        ],
      ),
    );
    if (status != 'found') {
      return SettingsListView(
        children: [
          header,
          _empty(
            context,
            status == 'test_account'
                ? 'Тестовый аккаунт HardPrepare.'
                : 'У этого Telegram ID пока нет связанных записей в HardPrepare.',
          ),
        ],
      );
    }
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            labelColor: c.textPrimary,
            unselectedLabelColor: c.textSecondary,
            indicatorColor: c.linkBlue,
            dividerColor: c.divider,
            tabs: const [
              Tab(text: 'Обзор'),
              Tab(text: 'Учёба'),
              Tab(text: 'Заявки и оплата'),
              Tab(text: 'История'),
            ],
          ),
          if (refreshing)
            const LinearProgressIndicator(semanticsLabel: 'Обновляем карточку'),
          Expanded(
            child: TabBarView(
              children: [
                _overview(context),
                _study(context),
                _orders(context),
                _history(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
