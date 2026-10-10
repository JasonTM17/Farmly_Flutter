import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import 'illustrations.dart';

/// Chat bubble. User: dark green with light ink; assistant: cream surface with
/// the sprout mark (spec 02 §6).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.isUser,
    required this.child,
    super.key,
  });

  final bool isUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.lg,
        vertical: FarmSpacing.md,
      ),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: isUser ? tokens.brandAction : tokens.surface,
        border: isUser ? null : Border.all(color: tokens.divider),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(tokens.cardRadius),
          topRight: Radius.circular(tokens.cardRadius),
          bottomLeft: Radius.circular(isUser ? tokens.cardRadius : 4),
          bottomRight: Radius.circular(isUser ? 4 : tokens.cardRadius),
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: isUser ? tokens.onAction : tokens.textPrimary,
        ),
        child: child,
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: isUser
          ? bubble
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SproutMark(size: 24),
                const SizedBox(width: FarmSpacing.xs),
                Flexible(child: bubble),
              ],
            ),
    );
  }
}

/// Composer: 48dp+ send target, grows to 5 lines then scrolls internally.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Nhập câu hỏi cho Farmly AI…',
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final bool enabled;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Container(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FarmSpacing.lg,
            FarmSpacing.sm,
            FarmSpacing.lg,
            FarmSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? onSend : null,
                  decoration: InputDecoration(hintText: hintText),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: FarmSpacing.sm),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = enabled && value.text.trim().isNotEmpty;
                  return Semantics(
                    button: true,
                    label: 'Gửi câu hỏi',
                    child: IconButton.filled(
                      onPressed: canSend ? () => onSend(controller.text) : null,
                      icon: const Icon(Icons.send),
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: FarmSpacing.minTouchTarget,
                        minHeight: FarmSpacing.minTouchTarget,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "New messages" jump control (spec 02 §4/§6 [NewMessagesButton]): shown
/// when the user has scrolled away from the bottom while new messages
/// arrived; tapping returns to the latest message.
class NewMessagesButton extends StatelessWidget {
  const NewMessagesButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      liveRegion: true,
      label: 'Có tin nhắn mới. Chạm để cuộn xuống tin nhắn mới nhất.',
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_downward, size: 18),
        label: const Text('Tin nhắn mới'),
      ),
    );
  }
}

/// "Dữ liệu đến … · nguồn …" footer under the assistant answer (spec 02 §6).
class ChatSourceFooter extends StatelessWidget {
  const ChatSourceFooter({required this.asOf, required this.source, super.key});

  final String asOf;
  final String source;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: FarmSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 14, color: tokens.textSecondary),
          const SizedBox(width: FarmSpacing.xs),
          Flexible(
            child: Text(
              'Dữ liệu đến $asOf · nguồn $source',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
