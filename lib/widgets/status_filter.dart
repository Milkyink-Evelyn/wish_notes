import 'package:flutter/material.dart';

/// 心愿状态筛选条: 全部 / 未实现 / 已实现
class WishStatusFilter extends StatelessWidget {
  final String? selectedStatus;
  final ValueChanged<String?> onChanged;

  const WishStatusFilter({
    super.key,
    required this.selectedStatus,
    required this.onChanged,
  });

  Widget _buildChip(String? status, String label) {
    final isSelected = selectedStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: Colors.pinkAccent.withValues(alpha: 0.2),
        onSelected: (_) => onChanged(status),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildChip(null, '全部'),
        _buildChip('UNREALIZED', '未实现'),
        _buildChip('REALIZED', '已实现'),
      ],
    );
  }
}