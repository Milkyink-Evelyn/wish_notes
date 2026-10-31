import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';
import '../logic/wish_list_model.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/cloud_import_pref.dart';
import '../utils/cloud_keep_ids.dart';
import '../utils/dialog_utils.dart';
import '../utils/toast_utils.dart';
import '../widgets/app_card.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const String _allUsersTag = '__ALL_USERS__';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthModel>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('个人中心')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _buildUserCard(context, auth),
          const SizedBox(height: 16),
          _buildSyncCard(context),
          const SizedBox(height: 16),
          _buildDataCard(context),
          if (auth.isLoggedIn) ...[
            const SizedBox(height: 24),
            _buildLogoutButton(context),
          ],
        ],
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, AuthModel auth) {
    final nickname = auth.isLoggedIn
        ? (auth.nickname?.isNotEmpty == true ? auth.nickname! : auth.username ?? '心愿用户')
        : '本地游客';
    final subtitle = auth.isLoggedIn
        ? '@${auth.username}'
        : '登录后可发布公开心愿, 多端同步';

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
            child: Text(
              nickname.isNotEmpty ? nickname.substring(0, 1) : '?',
              style: const TextStyle(
                fontSize: 24,
                color: Colors.pinkAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (!auth.isLoggedIn)
            TextButton(
              onPressed: () => _goLogin(context),
              child: const Text('去登录'),
            ),
        ],
      ),
    );
  }

  /// 云端心愿导入方式的当前值
  String _importModeLabel() {
    final mode = CloudImportPref.read();
    if (mode == StorageMode.cloud) return '自动存为云端';
    if (mode == StorageMode.smart) return '自动存为智能';
    return '每次询问';
  }

  /// 控制从云端新拉下来的心愿怎么存, 避免每次同步都弹窗
  Widget _buildSyncCard(BuildContext context) {
    final username = context.read<AuthModel>().username;

    return AppCard(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined, color: Colors.pinkAccent),
            title: const Text('云端心愿导入方式'),
            subtitle: Text('数组外的心愿: ${_importModeLabel()}'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _chooseImportMode(context),
          ),
          if (username != null && username.isNotEmpty) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            // 同步或清理后条数会变, 跟着确认集合的通知刷新
            ValueListenableBuilder<int>(
              valueListenable: CloudKeepIds.changes,
              builder: (context, _, __) {
                final keptCount = CloudKeepIds.count(username);
                return ListTile(
                  leading: const Icon(Icons.cloud_done_outlined, color: Colors.pinkAccent),
                  title: const Text('已确认保持云端'),
                  subtitle: Text('本机已记录 $keptCount 条, 同步时不再询问'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _clearKeepIds(context, username),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 清空后这些心愿下次同步会重新走导入方式或弹窗
  Future<void> _clearKeepIds(BuildContext context, String username) async {
    final count = CloudKeepIds.count(username);
    if (count == 0) {
      context.showSnack('还没有需要清理的确认记录');
      return;
    }

    final confirm = await showConfirmDialog(
      context,
      title: '清空确认记录',
      content: '确定清空 $count 条“保持云端”的确认记录吗？\n\n清空后这些心愿下次同步会重新询问存储方式。',
      confirmText: '清空',
    );
    if (confirm != true || !mounted || !context.mounted) return;

    await CloudKeepIds.clear(username);
    if (!mounted || !context.mounted) return;
    setState(() {});
    context.showSnack('已清空确认记录');
  }

  Future<void> _chooseImportMode(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('云端心愿导入方式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'ask'),
            child: const Text('每次询问'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, StorageMode.cloud.value),
            child: const Text('自动保存为云端'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, StorageMode.smart.value),
            child: const Text('自动保存为智能'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'ask') {
      await CloudImportPref.reset();
    } else {
      final mode = choice == StorageMode.cloud.value
          ? StorageMode.cloud
          : StorageMode.smart;
      await CloudImportPref.save(mode);
    }

    if (!mounted || !context.mounted) return;
    setState(() {});
    context.showSnack('已设置为${_importModeLabel()}');
  }

  /// 本地数据管理入口, 只清本机, 不动云端
  Widget _buildDataCard(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined, color: Colors.pinkAccent),
            title: const Text('按用户清理本地数据'),
            subtitle: const Text('选择某个账号或本地游客, 云端数据不受影响'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _clearByUser(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            title: const Text('清理全部本地数据'),
            subtitle: const Text('删除本机所有账号和游客的数据, 请谨慎操作'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _clearAllData(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(157, 255, 236, 243),
        borderRadius: BorderRadius.circular(30),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 30),
      child: TextButton(
        onPressed: () => _logout(context),
        child: const Text(
          '退出登录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
      ),
    );
  }

  /// 登录页返回后按当前账号重新加载列表
  Future<void> _goLogin(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );

    if (!context.mounted) return;
    final username = context.read<AuthModel>().username;
    await context.read<WishListModel>().loadLocalData(username);
  }

  /// 先列出本机出现过的归属者, 再选一个清理
  Future<void> _clearByUser(BuildContext context) async {
    final owners = await WishRepository().getLocalOwners();
    if (!context.mounted) return;

    if (owners.isEmpty) {
      context.showSnack('本地还没有可清理的数据');
      return;
    }

    final currentUsername = context.read<AuthModel>().username;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要清理的用户'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _allUsersTag),
            child: const Text('全部用户'),
          ),
          ...owners.map((owner) {
            final isCurrent = owner.isEmpty
                ? currentUsername == null
                : owner == currentUsername;
            final label = owner.isEmpty ? '本地游客' : owner;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, owner),
              child: Text(isCurrent ? '$label (当前)' : label),
            );
          }),
        ],
      ),
    );

    if (selected == null || !context.mounted) return;

    if (selected == _allUsersTag) {
      await _clearAllData(context);
      return;
    }

    await _clearOneUser(context, selected);
  }

  /// 只删本机数据, 云端数据保持不动
  Future<void> _clearOneUser(BuildContext context, String owner) async {
    final name = owner.isEmpty ? '本地游客' : owner;
    final confirm = await showConfirmDialog(
      context,
      title: '清理本地数据',
      content: '确定删除“$name”在本机的所有心愿吗？云端数据不会受影响。',
      confirmText: '清理',
    );
    if (confirm != true || !context.mounted) return;

    await WishRepository().clearLocalWishesByUsername(owner);
    await CloudKeepIds.clear(owner);
    if (!context.mounted) return;

    await context.read<WishListModel>().loadLocalData(context.read<AuthModel>().username);
    if (context.mounted) context.showSnack('$name 的本地数据已清理');
  }

  /// 清理全部本地数据, 这个操作不可恢复
  Future<void> _clearAllData(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: '清理全部本地数据',
      content: '确定删除本机所有账号和游客的心愿吗？这个操作不可恢复。',
      confirmText: '清理',
    );
    if (confirm != true || !context.mounted) return;

    await WishRepository().clearAllLocalWishes();
    await CloudKeepIds.clearAll();
    if (!context.mounted) return;

    await context.read<WishListModel>().loadLocalData(context.read<AuthModel>().username);
    if (context.mounted) context.showSnack('本地数据已清理');
  }

  /// 退出后回到游客视角, 重新加载无归属的本地数据
  Future<void> _logout(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: '退出登录',
      content: '确定要退出当前账号吗？',
      confirmText: '退出',
    );
    if (confirm != true || !context.mounted) return;

    await context.read<AuthModel>().logout();
    if (!context.mounted) return;

    await context.read<WishListModel>().loadLocalData(null);
    if (context.mounted) context.showSnack('已退出登录');
  }
}
