import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../logic/auth_model.dart';
import '../logic/wish_list_model.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/toast_utils.dart';
import '../widgets/custom_popup_menu.dart';
import '../widgets/wish_card.dart';
import 'wish_detail_page.dart';

class WishesPage extends StatelessWidget {
  const WishesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 Provider 将数据逻辑注入,并在创建时立刻读取本地数据
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            '心愿便签',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            unselectedLabelColor: Colors.grey,
            tabs: [
              Text('我的心愿'),
              Text('心愿广场'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MyWishesView(),
            _PublicWishesView(),
          ],
        ),
      ),
    );
  }
}

class _MyWishesView extends StatelessWidget {
  const _MyWishesView();

  @override
  Widget build(BuildContext context) {
    return Consumer<WishListModel>(
      builder: (context, model, child) {
        final currentUsername = context.read<AuthModel>().username;

        debugPrint('--- 列表刷新了,当前数据量: ${model.wishes.length} ---');

        if (model.isLoading && model.wishes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // 1. 归属者下拉框(仅在未登录且本地有数据时显示)
            _buildOwnerFilter(context, model, currentUsername),
            
            // 2. 分类
            _buildCategoryFilter(model),
            
            Expanded(
              child: model.displayWishes.isEmpty
                  ? _buildEmptyState(model, currentUsername)
                  : _buildWishList(model, currentUsername),
            ),
          ],
        );
      },
    );
  }

  /// 顶部分类筛选栏
  Widget _buildCategoryFilter(WishListModel model) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // “全部” Chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: model.selectedCategory == null,
              selectedColor: Colors.pinkAccent.withValues(alpha: 0.2),
              onSelected: (_) => model.setCategory(null),
            ),
          ),
          // 遍历所有分类
          ...WishCategory.values.map((cat) {
            final isSelected = model.selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(cat.label),
                avatar: Icon(
                  cat.icon, 
                  size: 16, 
                  color: isSelected ? Colors.white : cat.color,
                ),
                selected: isSelected,
                selectedColor: cat.color,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                ),
                showCheckmark: false,
                onSelected: (selected) {
                  model.setCategory(selected ? cat : null);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // 空状态视图
  Widget _buildEmptyState(WishListModel model, String? currentUsername) {
    final isFiltering = model.selectedCategory != null;
    return RefreshIndicator(
      onRefresh: () => model.syncAndRefresh(currentUsername),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Text(
              isFiltering 
                  ? '当前分类下还没有心愿哦~' 
                  : '还没有心愿哦,点击下方 + 号留下你的心愿吧~!',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // 数据列表视图
  Widget _buildWishList(WishListModel model, String? currentUsername) {
    return RefreshIndicator(
      onRefresh: () => model.syncAndRefresh(currentUsername),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: model.displayWishes.length + 1, 
        itemBuilder: (context, index) {
          if (index == model.displayWishes.length) {
            return const _ListFooter();
          }
          final wish = model.displayWishes[index];
          
          return WishCard(
            wish: wish,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WishDetailPage(wish: wish)),
              );
              if (context.mounted) model.loadLocalData(currentUsername);
            },
            onChangeStatus: () async {
              final repo = WishRepository();
              final nextStatus = wish.status == 'REALIZED' ? 'UNREALIZED' : 'REALIZED';
              final updated = wish.copyWith(status: nextStatus);
              await repo.updateWishLocal(updated);
              if (context.mounted) model.loadLocalData(currentUsername);
            },
            onDelete: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除心愿'),
                  content: const Text('确定要删除这个心愿吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false), 
                      child: const Text('取消')
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text('删除', style: TextStyle(color: Colors.red))
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                final repo = WishRepository();
                await repo.softDeleteWish(wish.localId!);
                if (context.mounted) model.loadLocalData(currentUsername);
              }
            },
          );
        },
      ),
    );
  }

  // 归属者筛选栏
  Widget _buildOwnerFilter(BuildContext context, WishListModel model, String? currentUsername) {
    // 如果已登录, 不需要看别人的本地数据，直接隐藏
    if (currentUsername != null) return const SizedBox.shrink();

    final owners = model.uniqueOwners;
    // 如果本地只有一种数据(全是游客，或者没有数据), 隐藏下拉框
    if (owners.isEmpty || (owners.length == 1 && owners.contains('__GUEST__'))) {
      return const SizedBox.shrink();
    }
    
    // 构建下拉选项数据 (使用 CustomPopupMenu 的数据格式)
    final menuItems = [
      PopupMenuItemData<String?>(value: null, label: '全部用户'),
      ...owners.map((owner) {
        return PopupMenuItemData<String?>(
          value: owner,
          label: owner == '__GUEST__' ? '本地游客' : owner,
        );
      }),
    ];

    // 当前选中显示的文本
    final displayText = model.selectedOwner == null
        ? '全部用户'
        : (model.selectedOwner == '__GUEST__'
            ? '本地游客'
            : model.selectedOwner!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('数据归属:', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: CustomPopupMenu<String?>(
                items: menuItems,
                onSelected: (val) => model.setOwner(val),
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
                      Text(
                        displayText,
                        style: const TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicWishesView extends StatefulWidget {
  const _PublicWishesView();

  @override
  State<_PublicWishesView> createState() => _PublicWishesViewState();
}

class _PublicWishesViewState extends State<_PublicWishesView> {
  final WishRepository _repo = WishRepository();

  List<WishModel> _wishes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _firstLoad();
  }

  /// 首次进入先读缓存, 再自动拉一次云端
  Future<void> _firstLoad() async {
    await _loadLocal();
    if (!mounted) return;
    await _refresh(showError: false);
  }

  /// 先读本地缓存, 让广场有内容可看
  Future<void> _loadLocal() async {
    try {
      final wishes = await _repo.getPublicWishes();
      if (!mounted) return;
      setState(() {
        _wishes = wishes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('读取广场缓存失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 下拉刷新: 拉云端公开心愿, 覆盖本地缓存
  Future<void> _refresh({bool showError = true}) async {
    try {
      await _repo.refreshPublicWishes(context.read<AuthModel>().username);
    } catch (e) {
      debugPrint('刷新广场失败: $e');
      if (mounted && showError) context.showSnack('广场刷新失败,先看看本地缓存吧~');
    } finally {
      await _loadLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _wishes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _wishes.isEmpty ? _buildEmptyState() : _buildWishList(),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 100),
        Center(
          child: Text(
            '广场还空空的, 下拉刷新看看吧~',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildWishList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: _wishes.length + 1,
      itemBuilder: (context, index) {
        if (index == _wishes.length) {
          return const _ListFooter();
        }

        final wish = _wishes[index];
        return WishCard(
          wish: wish,
          showMenu: false,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => WishDetailPage(wish: wish)),
            );
            if (mounted) _loadLocal();
          },
        );
      },
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 40, height: 1, color: Colors.grey.shade300),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '--- 已经到底啦 ---',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Container(width: 40, height: 1, color: Colors.grey.shade300),
        ],
      ),
    );
  }
}