import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';

/// Conflict comparison sheet (spec 02 §4/§7 [ConflictCompareSheet]): shows the
/// local proposal against the server current value with base version and
/// as-of, side by side and read-only. Resolution choices (keep server /
/// authorized replacement intent / encrypted draft) stay on the conflict card
/// so this sheet never mutates sync state.
void showConflictCompareSheet(
  BuildContext context, {
  required DemoSyncItem item,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ConflictCompareSheet(item: item),
  );
}

class ConflictCompareSheet extends StatelessWidget {
  const ConflictCompareSheet({required this.item, super.key});

  final DemoSyncItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          0,
          FarmSpacing.lg,
          FarmSpacing.lg,
        ),
        children: [
          Text(
            'So sánh xung đột',
            style: Theme.of(context).textTheme.titleLarge,
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            item.operationType,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.md),
          _CompareBlock(
            label: 'Bản của bạn (đề xuất)',
            value: item.localSummary,
            emphasized: true,
          ),
          const SizedBox(height: FarmSpacing.sm),
          _CompareBlock(
            label: 'Máy chủ (hiện tại)',
            value: item.serverSummary ?? 'Không có dữ liệu trên máy chủ',
            emphasized: false,
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            'Phiên gốc: ${item.baseVersion ?? 'không rõ'}'
            '${item.asOfLabel == null ? '' : ' · ${item.asOfLabel}'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            'Không có tự động gộp số liệu — chọn hướng xử lý trên thẻ xung đột.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareBlock extends StatelessWidget {
  const _CompareBlock({
    required this.label,
    required this.value,
    required this.emphasized,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(FarmSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FarmSpacing.md),
          border: Border.all(
            color: emphasized ? tokens.brandAction : tokens.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: emphasized ? tokens.brandAction : tokens.textSecondary,
              ),
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}
