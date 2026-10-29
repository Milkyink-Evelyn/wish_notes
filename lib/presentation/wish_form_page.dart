import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';
import '../utils/toast_utils.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';

class WishFormPage extends StatefulWidget {
  const WishFormPage({super.key});

  @override
  State<WishFormPage> createState() => _WishFormPageState();
}

class _WishFormPageState extends State<WishFormPage> {
  final _contentController = TextEditingController();

  WishCategory _selectedCategory = WishCategory.study;
  WishVisibility _selectedVisibility = WishVisibility.private;
  StorageMode _selectedMode = StorageMode.smart;

  bool _isSubmitting = false; // 防止重复点击保存

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveWish() async {
    final content = _contentController.text.trim();
    final currentUsername = context.read<AuthModel>().username;

    if (content.isEmpty) {
      context.showSnack('是不是忘记写心愿啦~?');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final newWish = WishModel(
        content: content,
        visibility: _selectedVisibility,
        status: 'UNREALIZED',
        storageMode: _selectedMode,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isDeleted: false,
        category: _selectedCategory,
        ownerUsername: currentUsername,
      );

      final repo = WishRepository();
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
        title: const Text('留下你的心愿吧~'),
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
          const Text('存储与可见性', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  if (newSelection.first == WishVisibility.public && !isLoggedIn) {
                    context.showSnack('未登录状态下无法发布公开心愿，请先去“我的”页面登录吧~');
                    return;
                  }

                  setState(() {
                    _selectedVisibility = newSelection.first;
                    if (_selectedVisibility == WishVisibility.public && _selectedMode == StorageMode.local) {
                      _selectedMode = StorageMode.smart;
                    }
                  });
                },
              ),
            ],
          ),

          // 存储模式选择
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
                    setState(() {
                      _selectedMode = newSelection.first;
                      // 规则：纯本地不支持公开
                      if (_selectedMode == StorageMode.local && _selectedVisibility == WishVisibility.public) {
                        _selectedVisibility = WishVisibility.private;
                        context.showSnack('公开心愿不能纯本地存储，已自动切为私有');
                      }
                    });
                  },
                ),
              ),
            ],
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
                    : const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
          )
        ],
      ),
    );
  }
}