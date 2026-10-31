import 'package:flutter/material.dart';
import '../models/wish_model.dart';

/// 云端新心愿的存储方式选择结果
class CloudWishSelection {
  final List<int> localIds;
  final StorageMode mode;
  final bool remember; // 是否记住这次选择, 以后不再询问

  const CloudWishSelection({
    required this.localIds,
    required this.mode,
    this.remember = false,
  });
}

/// 选择这次从云端新拉到本地的心愿要以什么方式保存
/// 返回 null 表示直接关掉了, 保持默认的云端存储
Future<CloudWishSelection?> showCloudWishPicker(
  BuildContext context,
  List<WishModel> wishes,
) {
  return showModalBottomSheet<CloudWishSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CloudWishPicker(wishes: wishes),
  );
}

class _CloudWishPicker extends StatefulWidget {
  final List<WishModel> wishes;

  const _CloudWishPicker({required this.wishes});

  @override
  State<_CloudWishPicker> createState() => _CloudWishPickerState();
}

class _CloudWishPickerState extends State<_CloudWishPicker> {
  late final Set<int> _selected;
  StorageMode _mode = StorageMode.cloud;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    // 默认全选, 用户按需要取消
    _selected = widget.wishes.map((e) => e.localId!).toSet();
  }

  bool get _allSelected => _selected.length == widget.wishes.length;

  /// 全选/取消全选
  void _toggleAll(bool? value) {
    setState(() {
      if (value == true) {
        _selected.addAll(widget.wishes.map((e) => e.localId!));
      } else {
        _selected.clear();
      }
    });
  }

  void _toggleOne(int localId, bool? value) {
    setState(() {
      if (value == true) {
        _selected.add(localId);
      } else {
        _selected.remove(localId);
      }
    });
  }

  void _confirm() {
    Navigator.pop(context, CloudWishSelection(
      localIds: _selected.toList(),
      mode: _mode,
      remember: _remember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '云端心愿',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              '发现 ${widget.wishes.length} 条本地没有的心愿, 选择要保存的存储方式',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Row(
              children: [
                Checkbox(value: _allSelected, onChanged: _toggleAll),
                Text(_allSelected ? '取消全选' : '全选'),
                const Spacer(),
                Text(
                  '已选 ${_selected.length} 条',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.wishes.length,
                itemBuilder: (context, index) {
                  final wish = widget.wishes[index];
                  final localId = wish.localId!;
                  return CheckboxListTile(
                    value: _selected.contains(localId),
                    onChanged: (value) => _toggleOne(localId, value),
                    title: Text(
                      wish.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('存储方式：'),
                const SizedBox(width: 12),
                SegmentedButton<StorageMode>(
                  segments: const [
                    ButtonSegment(value: StorageMode.cloud, label: Text('云端')),
                    ButtonSegment(value: StorageMode.smart, label: Text('智能')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    setState(() => _mode = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _mode == StorageMode.cloud
                  ? '云端：以服务器为准, 退出登录会清掉本地副本'
                  : '智能：本地和云端各存一份, 退出登录保留本地',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: (value) {
                    setState(() => _remember = value ?? false);
                  },
                ),
                const Expanded(
                  child: Text(
                    '以后自动按这个方式处理, 不再询问',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty ? null : _confirm,
                child: Text('确定 (${_selected.length} 条)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
