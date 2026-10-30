import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'custom_popup_menu.dart';

/// 单列/双列切换菜单, 样式和广场的排序菜单保持一致
class WishLayoutMenu extends StatelessWidget {
  final bool twoColumns;
  final ValueChanged<bool> onChanged;

  const WishLayoutMenu({
    super.key,
    required this.twoColumns,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPopupMenu<bool>(
      items: [
        PopupMenuItemData(
          value: false,
          label: '单列',
          textColor: twoColumns ? null : Colors.pinkAccent, // 当前选中项标粉
        ),
        PopupMenuItemData(
          value: true,
          label: '双列',
          textColor: twoColumns ? Colors.pinkAccent : null,
        ),
      ],
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              twoColumns ? '双列' : '单列',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
