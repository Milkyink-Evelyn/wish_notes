import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'sp_utils.dart';

/// 记录已经确认"保持云端存储"的云端心愿 serverId, 按账号分开存
/// 退出登录会清掉云端心愿, 重新登录拉回来时靠这份记录避免重复询问
class CloudKeepIds {
  CloudKeepIds._();

  /// 记录变化通知, 个人中心用它刷新"已记录 N 条"
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 读出所有账号的记录, 结构是 {用户名: [serverId]}
  static Map<String, Set<int>> _readAll() {
    final raw = SPUtils.getString(SPKey.cloudKeepIds);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final result = <String, Set<int>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          result[key.toString()] = value
              .whereType<num>()
              .map((e) => e.toInt())
              .toSet();
        }
      });
      return result;
    } catch (e) {
      debugPrint('解析已确认云端心愿失败: $e');
      return {};
    }
  }

  /// 某个账号已经确认过的心愿 serverId
  static Set<int> read(String? username) {
    if (username == null || username.isEmpty) return {};
    return _readAll()[username] ?? {};
  }

  /// 某个账号已确认的数量
  static int count(String? username) => read(username).length;

  /// 把这次确认保持云端的 serverId 记进去
  static Future<void> add(String? username, Iterable<int> serverIds) async {
    if (username == null || username.isEmpty) return;

    final all = _readAll();
    all.putIfAbsent(username, () => <int>{}).addAll(serverIds);
    await _save(all);
  }

  /// 只保留云端仍然存在的心愿, 清掉已经删掉的 serverId
  static Future<void> retain(String? username, Set<int> aliveIds) async {
    if (username == null || username.isEmpty) return;

    final all = _readAll();
    final current = all[username];
    if (current == null) return;

    current.removeWhere((id) => !aliveIds.contains(id));
    if (current.isEmpty) all.remove(username);
    await _save(all);
  }

  /// 清掉某个账号的确认记录
  static Future<void> clear(String? username) async {
    if (username == null || username.isEmpty) return;

    final all = _readAll();
    if (all.remove(username) == null) return;
    await _save(all);
  }

  /// 清掉所有账号的确认记录
  static Future<void> clearAll() async {
    await SPUtils.remove(SPKey.cloudKeepIds);
    changes.value++;
  }

  static Future<void> _save(Map<String, Set<int>> all) async {
    final data = all.map(
      (key, value) => MapEntry(key, value.toList()..sort()),
    );
    await SPUtils.setString(SPKey.cloudKeepIds, jsonEncode(data));
    changes.value++;
  }
}
