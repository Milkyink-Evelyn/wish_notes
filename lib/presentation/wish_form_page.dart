import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';
import '../utils/toast_utils.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';

class WishFormPage extends StatefulWidget {
  final WishModel? initialWish; // 传入时为编辑模式
  const WishFormPage({super.key, this.initialWish});

  @override
  State<WishFormPage> createState() => _WishFormPageState();
}

class _WishFormPageState extends State<WishFormPage> {
  final _contentController = TextEditingController();

  WishCategory _selectedCategory = WishCategory.study;
  WishVisibility _selectedVisibility = WishVisibility.private;
  StorageMode _selectedMode = StorageMode.smart;

  bool _isSubmitting = false; // 防止重复点击保存

  bool get _isEditing => widget.initialWish != null;

  /// 切换可见性, 本地存储不允许公开
  void _changeVisibility(WishVisibility next, bool isLoggedIn) {
    if (next == _selectedVisibility) return;

    if (next == WishVisibility.public) {
      if (!isLoggedIn) {
        context.showSnack('未登录状态下无法发布公开心愿,请先去“我的”页面登录吧~');
        return;
      }

      if (_selectedMode == StorageMode.local) {
        context.showSnack('本地存储不能设为公开, 请先切换存储模式');
        return;
      }
    }

    setState(() => _selectedVisibility = next);
  }

  /// 存储模式的中文名
  String _modeLabel(StorageMode mode) {
    if (mode == StorageMode.local) return '本地';
    if (mode == StorageMode.cloud) return '云端';
    return '智能';
  }

  /// 选存储模式时先提醒: 创建后不能改
  Future<void> _changeStorageMode(StorageMode next) async {
    if (next == _selectedMode) return;

    final label = _modeLabel(next);
    final desc = next == StorageMode.local
        ? '只保存在这台手机, 不上传云端。'
        : next == StorageMode.cloud
            ? '以服务器为准, 换设备登录也能看到。'
            : '本地和云端各存一份, 本地优先。';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认存储模式'),
        content: Text('$desc\n\n存储模式创建后不能修改, 本地存储不能设为公开。\n\n确定使用“$label”存储吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final wasPublic = _selectedVisibility == WishVisibility.public;
    setState(() {
      _selectedMode = next;
      // 纯本地不支持公开
      if (next == StorageMode.local && wasPublic) {
        _selectedVisibility = WishVisibility.private;
      }
    });

    if (next == StorageMode.local && wasPublic) {
      context.showSnack('本地存储不能公开, 已自动切为私有');
    }
  }

  @override
  void initState() {
    super.initState();

    final wish = widget.initialWish;
    if (wish != null) {
      _contentController.text = wish.content;
      _selectedCategory = wish.category;
      _selectedVisibility = wish.visibility;
      _selectedMode = wish.storageMode;

      // 旧版本可能留下纯本地+公开的脏数据, 打开编辑时按规则纠正
      if (wish.storageMode == StorageMode.local && wish.visibility == WishVisibility.public) {
        _selectedVisibility = WishVisibility.private;
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveWish() async {
    final content = _contentController.text.trim();
    final auth = context.read<AuthModel>();
    final currentUsername = auth.username;

    if (content.isEmpty) {
      context.showSnack('是不是忘记写心愿啦~?');
      return;
    }

    // 兜底: 公开心愿不能留在纯本地存储里
    if (_selectedVisibility == WishVisibility.public && _selectedMode == StorageMode.local) {
      context.showSnack('本地存储不能设为公开, 请先切换存储模式');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = WishRepository();

      if (_isEditing) {
        final original = widget.initialWish!;
        final updated = original.copyWith(
          content: content,
          visibility: _selectedVisibility,
          category: _selectedCategory,
          storageMode: _selectedMode,
        );
        await repo.updateWishLocal(updated);

        if (!mounted) return;
        debugPrint('--- 准备返回编辑结果 ---');
        Navigator.pop(context, updated);
        return;
      }

      final newWish = WishModel(
        content: content,
        visibility: _selectedVisibility,
        status: WishStatus.unrealized,
        storageMode: _selectedMode,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isDeleted: false,
        category: _selectedCategory,
        ownerUsername: currentUsername,
      );

      await repo.insertWish(newWish);

      if (!mounted) return;
      debugPrint('--- 准备返回 true ---');
      Navigator.pop(context, true);

    } catch (e) {
      if(!mounted) return;
      context.showSnack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthModel>().isLoggedIn;

    return Scaffold(
      backgroundColor: const Color.fromARGB(189, 255, 255, 255),
      appBar: AppBar(
        title: Text(_isEditing ? '编辑心愿' : '留下你的心愿吧~'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. 心愿内容输入区
          const Text('心愿内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: '写下你想做的事, 或者想留住的美好瞬间...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),

          // 2. 分类选择(本地)
          const Text('选择分类', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: WishCategory.values.map((cat) {
              return ChoiceChip(
                label: Text(cat.label),
                selected: _selectedCategory == cat,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedCategory = cat);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 3. 可见性与存储模式(公开的只能是智能/云端)
          Text(
            _isEditing ? '可见性' : '存储与可见性',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          // 可见性选择
          Row(
            children: [
              const Text('是否公开：'),
              const SizedBox(width: 16),
              SegmentedButton<WishVisibility>(
                segments: const [
                  ButtonSegment(value: WishVisibility.private, label: Text('私有')),
                  ButtonSegment(value: WishVisibility.public, label: Text('公开')),
                ],
                selected: {_selectedVisibility},
                onSelectionChanged: (Set<WishVisibility> newSelection) {
                  _changeVisibility(newSelection.first, isLoggedIn);
                },
              ),
            ],
          ),

          // 存储模式只在创建时可选, 选完就不能改了
          if (!_isEditing) ...[
            Row(
              children: [
                const Text('存储模式：'),
                const SizedBox(width: 16),
                Expanded(
                  child: SegmentedButton<StorageMode>(
                    segments: [
                      const ButtonSegment(value: StorageMode.local, label: Text('本地')),
                      const ButtonSegment(value: StorageMode.cloud, label: Text('云端')),
                      const ButtonSegment(value: StorageMode.smart, label: Text('智能')),
                    ],
                    selected: {_selectedMode},
                    onSelectionChanged: (Set<StorageMode> newSelection) {
                      _changeStorageMode(newSelection.first);
                    },
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '存储模式创建后不能修改, 本地存储不能设为公开',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
          // 编辑时只展示, 不能再改
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '存储模式：${_modeLabel(_selectedMode)}（创建后不可修改）',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(157, 193, 255, 241),
              borderRadius: BorderRadius.circular(30)
            ),
            margin: EdgeInsets.fromLTRB(30, 20, 30, 10),
            child: TextButton(
                onPressed: _isSubmitting ? null : _saveWish,
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2,),)
                    : Text(_isEditing ? '保存修改' : '保存', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
          )
        ],
      ),
    );
  }
}