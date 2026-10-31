import 'package:flutter/material.dart';
import '../logic/wish_list_model.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../widgets/cloud_wish_picker.dart';
import 'cloud_import_pref.dart';
import 'cloud_keep_ids.dart';
import 'toast_utils.dart';

/// 同步云端心愿
/// 已经确认保持云端的直接跳过, 其余按用户设置的默认存储方式处理, 没设置就弹窗
/// [showResult] 用于用户主动下拉的场景, 同步成功也给个轻提示
Future<void> syncWishesAndHandleNew(
  BuildContext context,
  WishListModel model,
  String? currentUsername, {
  bool showResult = false,
}) async {
  final result = await model.syncAndRefresh(currentUsername);
  if (!context.mounted) return;

  // 登录失效由主页面统一弹窗提醒, 这里不再重复提示
  if (!result.success) {
    if (!result.unauthorized) {
      context.showSnack(result.error ?? '同步失败, 请稍后重试');
    }
    return;
  }

  if (showResult) {
    context.showSnack(currentUsername == null ? '已刷新本地心愿' : '已同步最新心愿');
  }

  final newWishes = result.newWishes;
  final repo = WishRepository();

  // 云端已经删掉的心愿, 确认记录也一起清掉, 免得数组越积越多
  // 同步失败时本地数据可能不全, 不能拿来判断
  if (result.success && currentUsername != null && currentUsername.isNotEmpty) {
    final aliveIds = await repo.getLocalServerIds(currentUsername);
    await CloudKeepIds.retain(currentUsername, aliveIds);
  }
  if (!context.mounted || newWishes.isEmpty) return;

  // 确认过保持云端的不用再问, 剩下的才需要处理
  final keptIds = CloudKeepIds.read(currentUsername);
  final pending = newWishes
      .where((e) => e.serverId == null || !keptIds.contains(e.serverId))
      .toList();
  if (pending.isEmpty) return;

  final localIds = pending.map((e) => e.localId!).toList();
  final serverIds = pending
      .map((e) => e.serverId)
      .whereType<int>()
      .toList();

  // 已经设置过默认方式, 只处理数组外的心愿
  final preferred = CloudImportPref.read();
  if (preferred != null) {
    await repo.updateWishStorageMode(localIds, preferred);
    // 自动存为云端也算确认过, 下次不再询问
    if (preferred == StorageMode.cloud) {
      await CloudKeepIds.add(currentUsername, serverIds);
    }
    if (!context.mounted) return;

    await model.loadLocalData(currentUsername);
    if (!context.mounted) return;
    context.showSnack(
      '已自动保存 ${localIds.length} 条云端心愿为'
      '${preferred == StorageMode.smart ? '智能' : '云端'}存储',
    );
    return;
  }

  final selection = await showCloudWishPicker(context, pending);
  // 取消或手滑关掉都不记录, 下次同步继续询问
  if (selection == null || !context.mounted) return;

  await repo.updateWishStorageMode(selection.localIds, selection.mode);

  // 确认后仍然是云端的才记下来, 选成智能的不需要记
  if (selection.mode == StorageMode.cloud) {
    await CloudKeepIds.add(currentUsername, serverIds);
  } else {
    final selected = selection.localIds.toSet();
    final cloudIds = pending
        .where((e) => !selected.contains(e.localId))
        .map((e) => e.serverId)
        .whereType<int>();
    await CloudKeepIds.add(currentUsername, cloudIds);
  }

  // 勾选了"以后都这样处理"才记住, 否则下次导入继续询问
  if (selection.remember) {
    await CloudImportPref.save(selection.mode);
  }
  if (!context.mounted) return;

  await model.loadLocalData(currentUsername);
  if (!context.mounted) return;
  context.showSnack(
    selection.mode == StorageMode.cloud ? '已保存为云端存储' : '已保存为智能存储',
  );
}
