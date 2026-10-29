import 'package:flutter/material.dart';

class CustomPopupMenu<T> extends StatefulWidget {
  final Widget child; // 触发菜单的按钮（比如 ... 图标）
  final List<PopupMenuItemData<T>> items;
  final ValueChanged<T> onSelected;

  const CustomPopupMenu({
    super.key,
    required this.child,
    required this.items,
    required this.onSelected,
  });

  @override
  State<CustomPopupMenu<T>> createState() => _CustomPopupMenuState<T>();
}

class PopupMenuItemData<T> {
  final T value;
  final String label;
  final Color? textColor;

  PopupMenuItemData({required this.value, required this.label, this.textColor});
}

class _CustomPopupMenuState<T> extends State<CustomPopupMenu<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _closeMenu();
    } else {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 透明遮罩，点击任意地方关闭菜单
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
              child: Container(),
            ),
          ),
          // 悬浮菜单
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(-120 + size.width, size.height + 8), // 菜单向右对齐并向下偏移
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 140, // 菜单宽度
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12), // 圆角
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.items.map((item) {
                        return InkWell(
                          onTap: () {
                            widget.onSelected(item.value);
                            _closeMenu();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: item.textColor ?? Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleMenu,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      ),
    );
  }
}