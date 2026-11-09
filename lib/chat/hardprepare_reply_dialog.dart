import 'package:flutter/material.dart';

import '../components/app_dialog.dart';
import '../components/app_interactive_surface.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'hardprepare_reply_service.dart';

Future<String?> showHardPrepareReplyDialog(
  BuildContext context,
  HardPrepareReplyService service,
) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Закрыть',
  barrierColor: Colors.black54,
  transitionDuration: AppMotion.duration(context, AppMotion.responsive),
  transitionBuilder: AppMotion.dialogTransition,
  pageBuilder: (_, _, _) => _HardPrepareReplyDialog(service: service),
);

class _HardPrepareReplyDialog extends StatefulWidget {
  const _HardPrepareReplyDialog({required this.service});

  final HardPrepareReplyService service;

  @override
  State<_HardPrepareReplyDialog> createState() =>
      _HardPrepareReplyDialogState();
}

class _HardPrepareReplyDialogState extends State<_HardPrepareReplyDialog> {
  final _brief = TextEditingController();
  String? _reply;
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    widget.service.close();
    _brief.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_working || _brief.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final reply = await widget.service.suggest(_brief.text);
      if (mounted) setState(() => _reply = reply);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          HardPrepareReplyError(:final message) => message,
          FormatException() => 'Сервис вернул ответ в неизвестном формате.',
          _ => 'Не удалось связаться с моделью. Проверьте адрес и соединение.',
        };
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reply = _reply;
    final muted = readableLinkColor(
      background: colors.card,
      preferred: colors.textSecondary,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AppDialogSurface(
        title: 'Ответ HardPrepare',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reply == null) ...[
              Text(
                'Опишите вопрос своими словами. Модель получит только этот текст.',
                style: AppTextStyle.body(muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _brief,
                readOnly: _working,
                minLines: 3,
                maxLines: 5,
                maxLength: hardPrepareBriefLimit,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() => _error = null),
                style: AppTextStyle.body(colors.dialogText),
                decoration: InputDecoration(
                  labelText: 'Вопрос клиента',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Например, как записаться на пробный NUET',
                  hintMaxLines: 2,
                  filled: true,
                  fillColor: colors.searchFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
              Text(
                '${widget.service.model} • ${widget.service.host}',
                style: AppTextStyle.footnote(muted),
              ),
              if (_working || _error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ?? 'Модель готовит черновик…',
                    style: AppTextStyle.body(
                      _error == null ? muted : colors.dialogText,
                    ),
                  ),
                ),
              ],
            ] else ...[
              SelectableText(
                reply,
                style: AppTextStyle.body(colors.dialogText),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Проверьте детали. Текст можно отредактировать после вставки.',
                style: AppTextStyle.footnote(muted),
              ),
            ],
          ],
        ),
        actions: [
          _action(
            reply == null ? 'Закрыть' : 'К вопросу',
            reply == null
                ? () => Navigator.of(context).pop()
                : () => setState(() => _reply = null),
          ),
          _action(
            reply == null ? 'Подсказать' : 'Вставить',
            reply != null
                ? () => Navigator.of(context).pop(reply)
                : !_working && _brief.text.trim().isNotEmpty
                ? _suggest
                : null,
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback? onTap, {bool primary = false}) {
    final colors = context.colors;
    final color = onTap == null
        ? colors.textTertiary
        : readableLinkColor(
            background: colors.card,
            preferred: primary ? colors.dialogButton : colors.textSecondary,
          );
    return Expanded(
      child: AppInteractiveSurface(
        semanticLabel: label,
        enabled: onTap != null,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: AppTextStyle.bodyLarge(
                  color,
                  weight: primary ? AppTextWeight.semibold : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
