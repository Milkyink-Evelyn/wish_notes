import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../logic/auth_model.dart';
import '../logic/wish_list_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/toast_utils.dart';
import 'login_page_test.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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

  Widget _buildDataCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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

  Future<void> _goLogin(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );

    if (!context.mounted) return;
    final username = context.read<AuthModel>().username;
    await context.read<WishListModel>().loadLocalData(username);
  }

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

  Future<void> _clearOneUser(BuildContext context, String owner) async {
    final name = owner.isEmpty ? '本地游客' : owner;
    final confirm = await _confirm(
      context,
      title: '清理本地数据',
      content: '确定删除“$name”在本机的所有心愿吗？云端数据不会受影响。',
    );
    if (confirm != true || !context.mounted) return;

    await WishRepository().clearLocalWishesByUsername(owner);
    if (!context.mounted) return;

    await context.read<WishListModel>().loadLocalData(context.read<AuthModel>().username);
    if (context.mounted) context.showSnack('$name 的本地数据已清理');
  }

  Future<void> _clearAllData(BuildContext context) async {
    final confirm = await _confirm(
      context,
      title: '清理全部本地数据',
      content: '确定删除本机所有账号和游客的心愿吗？这个操作不可恢复。',
    );
    if (confirm != true || !context.mounted) return;

    await WishRepository().clearAllLocalWishes();
    if (!context.mounted) return;

    await context.read<WishListModel>().loadLocalData(context.read<AuthModel>().username);
    if (context.mounted) context.showSnack('本地数据已清理');
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await _confirm(
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

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '清理',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
