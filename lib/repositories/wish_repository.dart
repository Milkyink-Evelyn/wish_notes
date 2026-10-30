import 'package:flutter/material.dart' show debugPrint;
import 'package:wish_notes/utils/wish_api.dart';
import '../utils/db_utils.dart';
import '../models/wish_model.dart';

class WishRepository {
  final WishApi _api;

  WishRepository({WishApi? api}) : _api = api ?? WishApi();

  /// 获取本地所有心愿(不包含软删除)
  /// ownerUsername 为空时返回本机全部账号和游客的数据, 游客视角就是这样看的
  Future<List<WishModel>> getMyWishes({String? ownerUsername}) async {
    final db = DBUtils.db;
    String where = '${WishTable.colIsDeleted} = 0 AND ${WishTable.colIsPublicCache} = 0';
    List<dynamic> whereArgs = [];

    if (ownerUsername != null) {
      where += ' AND ${WishTable.colOwnerUsername} = ?';
      whereArgs.add(ownerUsername);
    }

    final maps = await db.query(
      WishTable.name,
      where: where,
      whereArgs: whereArgs,
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

  /// 从云端拉取广场公开心愿,覆盖本地缓存
  Future<void> refreshPublicWishes(String? currentUsername) async {
    final db = DBUtils.db;
    final cloudList = await _api.fetchPublicWishes();
    final Set<int> cloudServerIds = {};

    for (var json in cloudList) {
      final cloudWish = WishModel.fromJson(json, StorageMode.smart);
      final serverId = cloudWish.serverId;
      if (serverId == null) continue;
      cloudServerIds.add(serverId);

      final isMine = currentUsername != null && cloudWish.ownerUsername == currentUsername;

      final localMaps = await db.query(
        WishTable.name,
        where: '${WishTable.colServerId} = ?',
        whereArgs: [serverId],
      );

      if (localMaps.isNotEmpty) {
        final localWish = WishModel.fromMap(localMaps.first);

        if (localWish.isDeleted) continue; // 本地有墓碑, 交给同步流程处理
        if (!localWish.isPublicCache) continue; // 自己或其他账号的真实数据, 广场刷新不动

        final updateMap = cloudWish.toMap();
        updateMap[WishTable.colLocalId] = localWish.localId;
        updateMap[WishTable.colCategory] = localWish.category.name;
        updateMap[WishTable.colIsPublicCache] = isMine ? 0 : 1;
        // 自己的心愿从广场缓存转正, 本地没有正本, 按云端专属处理
        updateMap[WishTable.colStorageMode] =
            isMine ? StorageMode.cloud.value : localWish.storageMode.value;
        await db.update(
          WishTable.name,
          updateMap,
          where: '${WishTable.colLocalId} = ?',
          whereArgs: [localWish.localId],
        );
      } else { // 本地没有, 插入一份缓存
        final insertMap = cloudWish.toMap();
        insertMap.remove(WishTable.colLocalId);
        insertMap[WishTable.colIsPublicCache] = isMine ? 0 : 1;
        // 自己的公开心愿第一次在广场里碰到, 本地同样没有正本
        if (isMine) insertMap[WishTable.colStorageMode] = StorageMode.cloud.value;
        await db.insert(WishTable.name, insertMap);
      }
    }

    // 清理云端已经看不到的广场缓存(只删缓存, 不动自己的数据)
    final cachedMaps = await db.query(
      WishTable.name,
      where: '${WishTable.colIsPublicCache} = 1',
    );

    for (var map in cachedMaps) {
      final localWish = WishModel.fromMap(map);
      if (localWish.serverId != null && !cloudServerIds.contains(localWish.serverId)) {
        await db.delete(
          WishTable.name,
          where: '${WishTable.colLocalId} = ?',
          whereArgs: [localWish.localId],
        );
      }
    }
  }

  /// 保存心愿(本地)
  Future<int> insertWish(WishModel wish) async {
    final db = DBUtils.db;
    
    return await db.insert(
      WishTable.name,
      wish.toMap(),
    );
  }

  /// 删除心愿: 没上过云的直接物理删除, 上过云的打墓碑等同步
  Future<void> deleteWish(int localId) async {
    final db = DBUtils.db;

    final maps = await db.query(
      WishTable.name,
      columns: [WishTable.colServerId],
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (maps.isEmpty) return;

    if (maps.first[WishTable.colServerId] == null) { // 云端没有副本, 墓碑永远同步不掉
      await db.delete(
        WishTable.name,
        where: '${WishTable.colLocalId} = ?',
        whereArgs: [localId],
      );
      return;
    }

    await db.update(
      WishTable.name,
      {WishTable.colIsDeleted: 1},
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
    );
  }

  /// 从云端拉取我的心愿,并合并到本地(智能模式同步数据)
  Future<void> pullMyWishes(String currentUsername) async {
    final db = DBUtils.db;
    final cloudList = await _api.fetchMyWishes();
    final Set<int> cloudServerIds = {}; // 清理僵尸数据用

    for (var json in cloudList) {
      var cloudWish = WishModel.fromJson(json, StorageMode.cloud);
      // /wishes/me 只返回当前用户的数据, 后端漏了用户名就直接补上
      if (cloudWish.ownerUsername == null) {
        cloudWish = cloudWish.copyWith(ownerUsername: currentUsername);
      }
      cloudServerIds.add(cloudWish.serverId!);

      // 先按 serverId 找, 兼容之前被当成广场缓存存下来的情况
      final localMaps = await db.query(
        WishTable.name,
        where: '${WishTable.colServerId} = ?',
        whereArgs: [cloudWish.serverId],
        orderBy: '${WishTable.colIsPublicCache} ASC', // 真实数据排在缓存前面
      );

      if (localMaps.isNotEmpty) {
        final localWish = WishModel.fromMap(localMaps.first);

        if (localWish.isDeleted) { // 本地数据已软删除, 不做处理
          continue;
        }

        if (!localWish.isPublicCache &&
            localWish.ownerUsername != null &&
            localWish.ownerUsername != currentUsername) { // 数据异常, 不覆盖别人的本地记录
          continue;
        }

        if (localWish.isPublicCache) { // 广场缓存转为真实数据, 作者就是当前用户
          final updateMap = cloudWish.toMap();
          updateMap[WishTable.colLocalId] = localWish.localId;
          updateMap[WishTable.colCategory] = localWish.category.name;
          updateMap[WishTable.colIsPublicCache] = 0;
          // 本地之前只有缓存, 没有正本, 按云端专属处理
          updateMap[WishTable.colStorageMode] = StorageMode.cloud.value;
          await db.update(
            WishTable.name,
            updateMap,
            where: '${WishTable.colLocalId} = ?',
            whereArgs: [localWish.localId],
          );
        } else if (localWish.storageMode == StorageMode.cloud) { // 云端存储以服务器为准
          final updateMap = cloudWish.toMap();
          updateMap[WishTable.colLocalId] = localWish.localId;
          updateMap[WishTable.colCategory] = localWish.category.name; // 后端没有分类字段, 保留本地的
          await db.update(
            WishTable.name,
            updateMap,
            where: '${WishTable.colLocalId} = ?',
            whereArgs: [localWish.localId],
          );
        } else if (localWish.visibility == WishVisibility.public) { // 公开心愿智能存储同步以服务器为主
          final updateMap = cloudWish.toMap();
          updateMap[WishTable.colLocalId] = localWish.localId;
          updateMap[WishTable.colCategory] = localWish.category.name; // 后端没有分类字段, 保留本地的
          updateMap[WishTable.colStorageMode] = localWish.storageMode.value; // 别把本地的存储模式冲掉
          await db.update(
            WishTable.name,
            updateMap,
            where: '${WishTable.colLocalId} = ?',
            whereArgs: [localWish.localId],
          );
        }// 私有心愿智能存储同步以本地为主, 不作修改
      } else {  // 本地数据缺失/丢失,用云端数据恢复, 本地没正本, 记成云端专属
        final insertMap = cloudWish.toMap();
        insertMap.remove(WishTable.colLocalId);
        await db.insert(WishTable.name, insertMap);
      }
    }

    // 处理云端被删除的数据而本地仍存在的僵尸数据
    final localSyncedWishes = await db.query(
      WishTable.name,
      where: '${WishTable.colServerId} IS NOT NULL AND ${WishTable.colIsDeleted} = 0 AND ${WishTable.colOwnerUsername} = ?',
      whereArgs: [currentUsername],
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
  Future<void> syncDeletedWishes(String currentUsername) async {
    final db = DBUtils.db;
    final deletedMaps = await db.query(
      WishTable.name,
      where: '${WishTable.colIsDeleted} = ? AND ${WishTable.colServerId} IS NOT NULL AND ${WishTable.colOwnerUsername} = ?',
      whereArgs: [1, currentUsername],
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
  Future<void> pushNewWishes(String currentUsername) async {
    final db = DBUtils.db;

    final unsyncedMaps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [StorageMode.local.value, currentUsername],
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
  Future<void> pushUpdatedStatus(String currentUsername) async {
    final db = DBUtils.db;
    // 查出所有：已同步过(server_id不为空)、未删除、非纯本地 且 状态与云端不一致的心愿
    // (因为本地没有记录云端上一次的状态,为了简单,我们这里全量推送本地的状态)
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [StorageMode.local.value, currentUsername],
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
  Future<void> pushUpdatedWishes(String currentUsername) async {
    final db = DBUtils.db;

    // 查出所有已同步过、未删除、非纯本地的数据
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [StorageMode.local.value, currentUsername],
    );

    for (var map in maps) {
      final localWish = WishModel.fromMap(map);
      
      // 公开、私有都推送: 公开心愿需要登录作者才能修改, 改完要覆盖云端
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
  }

  /// 完整的云端同步流程
  Future<void> syncAll(String? currentUsername) async {
    if (currentUsername == null || currentUsername.isEmpty) {
      debugPrint('未登录, 跳过云端同步');
      return;
    }
    
    try {
      debugPrint('--- 开始同步 ---');
      
      // 1. 云端删除(处理本地软删除的墓碑)
      await syncDeletedWishes(currentUsername);
      
      // 2. 推送新建(把本地没上过云的心愿传上去)
      await pushNewWishes(currentUsername);
      
      // 3. 推送修改(把本地修改过的内容和状态传上去)
      await pushUpdatedWishes(currentUsername);
      await pushUpdatedStatus(currentUsername);
      
      // 4. 拉取合并(最后拉取,获取云端最新数据)
      await pullMyWishes(currentUsername);
      
      debugPrint('--- 同步完成 ---');
    } catch (e) {
      debugPrint('同步过程中发生错误: $e');
      rethrow; // 抛给 UI 层去弹窗提示
    }
  }

  /// 更新本地心愿数据(用于切换状态)
  Future<void> updateWishLocal(WishModel wish) async {
    final db = DBUtils.db;
    await db.update(
      WishTable.name,
      wish.toMap(),
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [wish.localId],
    );
  }

  /// 获取本地真实数据里出现过的归属者(不含广场缓存), 游客用空字符串表示
  Future<List<String>> getLocalOwners() async {
    final db = DBUtils.db;
    final maps = await db.query(
      WishTable.name,
      columns: [WishTable.colOwnerUsername],
      where: '${WishTable.colIsPublicCache} = 0',
      groupBy: WishTable.colOwnerUsername,
      orderBy: WishTable.colOwnerUsername,
    );

    return maps.map((e) => e[WishTable.colOwnerUsername] as String? ?? '').toList();
  }

  /// 统计本机没有归属账号的心愿(含本地私有、广场缓存除外)
  Future<int> countOrphanWishes() async {
    final db = DBUtils.db;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total FROM ${WishTable.name}
      WHERE ${WishTable.colOwnerUsername} IS NULL
        AND ${WishTable.colIsPublicCache} = 0
        AND ${WishTable.colIsDeleted} = 0
      ''',
    );

    return (result.first['total'] as int?) ?? 0;
  }

  /// 把本机没有归属账号的心愿归到指定账号, 返回认领数量
  Future<int> claimOrphanWishes(String username) async {
    final db = DBUtils.db;
    return await db.update(
      WishTable.name,
      {WishTable.colOwnerUsername: username},
      where: '''
        ${WishTable.colOwnerUsername} IS NULL
        AND ${WishTable.colIsPublicCache} = 0
        AND ${WishTable.colIsDeleted} = 0
      ''',
    );
  }

  /// 退出登录时清掉只存在云端的心愿(公开和私有)
  /// 这类数据本地只是副本, 重新登录还能从云端拉回来
  /// 广场缓存和墓碑不动, 前者还要继续给广场用, 后者留给下次同步删除云端
  /// 还没上传成功的(serverId 为空)也不动, 否则会丢数据
  Future<void> clearCloudWishes() async {
    final db = DBUtils.db;
    await db.delete(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL
        AND ${WishTable.colStorageMode} = ?
        AND ${WishTable.colIsPublicCache} = 0
        AND ${WishTable.colIsDeleted} = 0
      ''',
      whereArgs: [StorageMode.cloud.value],
    );
  }

  /// 直接清空所有本地心愿(物理删除)
  Future<void> clearAllLocalWishes() async {
    final db = DBUtils.db;
    await db.delete(WishTable.name);
  }

  /// 指定清理某个用户或游客的本地心愿(物理删除)
  Future<void> clearLocalWishesByUsername(String? username) async {
    final db = DBUtils.db;

    if (username == null || username.isEmpty) {
      await db.delete(
        WishTable.name,
        where: '${WishTable.colOwnerUsername} IS NULL',
      );
      return;
    }

    await db.delete(
      WishTable.name,
      where: '${WishTable.colOwnerUsername} = ?',
      whereArgs: [username],
    );
  }
}