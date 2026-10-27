import 'package:flutter/material.dart' show debugPrint;
import 'package:wish_notes/utils/wish_api.dart';
import '../utils/db_utils.dart';
import '../models/wish_model.dart';

class WishRepository {
  final WishApi _api = WishApi();

  /// 获取本地所有心愿(不包含软删除)
  Future<List<WishModel>> getMyWishes() async {
    final db = DBUtils.db;

    final maps = await db.query(
      WishTable.name,
      where: '${WishTable.colIsDeleted} = ?',
      whereArgs: [0],
      orderBy: '${WishTable.colCreatedAt} DESC',
    );

    return maps.map((e) => WishModel.fromMap(e)).toList();
  }

  /// 获取本地存储的心愿广场的公开心愿
  Future<List<WishModel>> getPublicWishes() async {
    final db = DBUtils.db;

    final maps = await db.query(
      WishTable.name,
      where: '${WishTable.colIsDeleted} = ? AND ${WishTable.colVisibility} = ?',
      whereArgs: [0, WishVisibility.public.value],
      orderBy: '${WishTable.colCreatedAt} DESC',
    );

    return maps.map((e) => WishModel.fromMap(e)).toList();
  }

  /// 保存心愿(本地)
  Future<int> insertWish(WishModel wish) async {
    final db = DBUtils.db;
    
    return await db.insert(
      WishTable.name,
      wish.toMap(),
    );
  }

  /// 墓碑软删除(本地)
  Future<void> softDeleteWish(int localId) async {
    final db = DBUtils.db;
    
    await db.update(
      WishTable.name,
      {WishTable.colIsDeleted: 1},
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
    );
  }

  /// 从云端拉取我的心愿，并合并到本地(智能模式同步数据)
  Future<void> pullMyWishes() async {
    final db = DBUtils.db;
    final cloudList = await _api.fetchMyWishes();
    final Set<int> cloudServerIds = {}; // 清理僵尸数据用

    for (var json in cloudList) {
      final cloudWish = WishModel.fromJson(json, StorageMode.smart);
      cloudServerIds.add(cloudWish.serverId!);

      // 查询本地是否有该云端记录
      final localMaps = await db.query(
        WishTable.name,
        where: '${WishTable.colServerId} = ?',
        whereArgs: [cloudWish.serverId],
      );

      if (localMaps.isNotEmpty) {
        final localWish = WishModel.fromMap(localMaps.first);

        if (localWish.isDeleted) { // 本地数据已软删除, 不做处理
          continue;
        }

        if (localWish.visibility == WishVisibility.public) { // 公开心愿智能存储同步以服务器为主
          final updateMap = cloudWish.toMap();
          updateMap[WishTable.colLocalId] = localWish.localId;
          updateMap[WishTable.colIsDeleted] = localWish.isDeleted ? 1 : 0;
          await db.update(
            WishTable.name,

            updateMap,
            where: '${WishTable.colLocalId} = ?',
            whereArgs: [localWish.localId],
          );
        }// 私有心愿智能存储同步以本地为主, 不作修改
      } else {  // 本地数据缺失/丢失，用云端数据恢复
        final insertMap = cloudWish.toMap();
        insertMap.remove(WishTable.colLocalId);
        await db.insert(WishTable.name, insertMap);
      }
    }

    // 处理云端被删除的数据而本地仍存在的僵尸数据
    final localSyncedWishes = await db.query(
      WishTable.name,
      where: '${WishTable.colServerId} IS NOT NULL AND ${WishTable.colIsDeleted} = 0',
    );

    for (var map in localSyncedWishes) {
      final localWish = WishModel.fromMap(map);
      if (!cloudServerIds.contains(localWish.serverId)) {
        await db.delete(
          WishTable.name,
          where: '${WishTable.colLocalId} = ?',
          whereArgs: [localWish.localId], 
        );
      }
    }
  }

  /// 处理墓碑软删除
  Future<void> syncDeletedWishes() async {
    final db = DBUtils.db;
    final deletedMaps = await db.query(
      WishTable.name,
      where: '${WishTable.colIsDeleted} = ? AND ${WishTable.colServerId} IS NOT NULL',
      whereArgs: [1],
    );

    for (var map in deletedMaps) {
      final serverId = map[WishTable.colServerId] as int;
      final localId = map[WishTable.colLocalId] as int;

      try {
        await _api.deleteWish(serverId);
        await db.delete(
          WishTable.name,
          where: '${WishTable.colLocalId} = ?',
          whereArgs: [localId],
        );
      } catch (e) {
        debugPrint('云端删除失败 serverId=$serverId: $e');
      }
    }
  }

  /// 将本地新建的智能/云端心愿推送到服务器
  Future<void> pushNewWishes() async {
    final db = DBUtils.db;

    final unsyncedMaps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
      ''',
      whereArgs: [StorageMode.local.value],
    );

    for (var map in unsyncedMaps) {
      final localWish = WishModel.fromMap(map);

      try {
        final cloudData = await _api.createWish(
          localWish.content,
          localWish.visibility.value,
        );

        final serverId = cloudData['id'] as int;
        await db.update(
          WishTable.name,
          {WishTable.colServerId: serverId},
          where: '${WishTable.colLocalId} = ?',
          whereArgs: [localWish.localId],
        );
      } catch (e) {
        debugPrint('推送新建心愿失败 localId=${localWish.localId}: $e');
      }
    }
  }

  /// 将本地已修改状态的心愿推送到云端
  Future<void> pushUpdatedStatus() async {
    final db = DBUtils.db;
    // 查出所有：已同步过(server_id不为空)、未删除、非纯本地 且 状态与云端不一致的心愿
    // (因为本地没有记录云端上一次的状态,为了简单,我们这里全量推送本地的状态)
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
      ''',
      whereArgs: [StorageMode.local.value],
    );

    for (var map in maps) {
      final localWish = WishModel.fromMap(map);
      try {
        await _api.updateWishStatus(localWish.serverId!, localWish.status);
      } catch (e) {
        debugPrint('推送状态失败 localId=${localWish.localId}: $e');
      }
    }
  }

  /// 推送本地修改过内容/可见性的心愿到云端
  Future<void> pushUpdatedWishes() async {
    final db = DBUtils.db;

    // 查出所有已同步过、未删除、非纯本地的数据
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
      ''',
      whereArgs: [StorageMode.local.value],
    );

    for (var map in maps) {
      final localWish = WishModel.fromMap(map);
      
      // 私有心愿以本地为准，所以推送覆盖云端
      if (localWish.visibility == WishVisibility.private) {
        try {
          await _api.updateWish(
            localWish.serverId!, 
            localWish.content, 
            localWish.visibility.value
          );
        } catch (e) {
          debugPrint('推送修改心愿失败 localId=${localWish.localId}: $e');
        }
      }
      // 公开心愿未登录不可更改，不作操作。
    }
  }

  /// 完整的智能同步流程
  Future<void> syncAll() async {
    try {
      debugPrint('--- 开始同步 ---');
      
      // 1. 云端删除(处理本地软删除的墓碑)
      await syncDeletedWishes();
      
      // 2. 推送新建(把本地没上过云的心愿传上去)
      await pushNewWishes();
      
      // 3. 推送修改(把本地修改过的内容和状态传上去)
      await pushUpdatedWishes();
      await pushUpdatedStatus();
      
      // 4. 拉取合并(最后拉取，获取云端最新数据)
      await pullMyWishes();
      
      debugPrint('--- 同步完成 ---');
    } catch (e) {
      debugPrint('同步过程中发生错误: $e');
      rethrow; // 抛给 UI 层去弹窗提示
    }
  }
}