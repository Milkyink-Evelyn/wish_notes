import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:wish_notes/utils/wish_api.dart';
import '../utils/cloud_keep_ids.dart';
import '../utils/db_utils.dart';
import '../models/wish_model.dart';

/// 单条心愿推送到云端的结果
enum CloudPushResult {
  success,      // 推上去了, 或者本来就不需要推
  failed,       // 网络/服务端失败, 保留脏标记等下次同步
  unauthorized, // 登录失效, 交给全局弹窗提醒
}

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
  /// 返回本地原本没有、这次新插入的心愿, 交给界面选择存储方式
  Future<List<WishModel>> pullMyWishes(String currentUsername) async {
    final db = DBUtils.db;
    final cloudList = await _api.fetchMyWishes();
    final Set<int> cloudServerIds = {}; // 清理僵尸数据用
    final List<WishModel> newWishes = []; // 本地缺失, 这次新拉下来的

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
        } else if (localWish.storageMode == StorageMode.local) { // 纯本地不参与云端合并
          continue;
        } else { // 按字段合并: 本地改过的保留本地, 没改过的接受云端
          final merged = _mergeCloudWish(localWish, cloudWish);
          debugPrint(
            '合并心愿 serverId=${cloudWish.serverId} '
            '内容脏=${merged.contentDirty} 状态脏=${merged.statusDirty}'
          );
          await db.update(
            WishTable.name,
            merged.toMap(),
            where: '${WishTable.colLocalId} = ?',
            whereArgs: [localWish.localId],
          );
        }
      } else {  // 本地数据缺失/丢失,用云端数据恢复, 本地没正本, 默认按云端专属处理
        final insertMap = cloudWish.toMap();
        insertMap.remove(WishTable.colLocalId);
        final localId = await db.insert(WishTable.name, insertMap);
        newWishes.add(WishModel.fromMap({
          ...insertMap,
          WishTable.colLocalId: localId,
        }));
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

    return newWishes;
  }

  /// 合并云端数据: 本地有未同步修改的字段保留本地, 其余字段接受云端
  WishModel _mergeCloudWish(WishModel local, WishModel cloud) {
    return WishModel(
      localId: local.localId,
      serverId: cloud.serverId,
      content: local.contentDirty ? local.content : cloud.content,
      visibility: local.contentDirty ? local.visibility : cloud.visibility,
      status: local.statusDirty ? local.status : cloud.status,
      storageMode: local.storageMode, // 存储模式只在创建时确定
      createdAt: cloud.createdAt,
      isDeleted: local.isDeleted,
      category: local.category, // 后端没有分类字段, 永远用本地的
      comments: cloud.comments,
      ownerUsername: cloud.ownerUsername ?? local.ownerUsername,
      isPublicCache: local.isPublicCache,
      contentDirty: local.contentDirty,
      statusDirty: local.statusDirty,
    );
  }

  /// 处理墓碑软删除
  /// 广场缓存不属于自己, 不能拿去删云端
  Future<void> syncDeletedWishes(String currentUsername) async {
    final deletedMaps = await DBUtils.db.query(
      WishTable.name,
      where: '''
        ${WishTable.colIsDeleted} = ?
        AND ${WishTable.colServerId} IS NOT NULL
        AND ${WishTable.colIsPublicCache} = 0
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [1, currentUsername],
    );

    for (var map in deletedMaps) {
      final serverId = map[WishTable.colServerId] as int;
      final localId = map[WishTable.colLocalId] as int;
      await _deleteCloudRow(serverId, localId);
    }
  }

  /// 删除云端记录, 成功后把本地墓碑一起清掉
  /// 404 说明云端本来就没有了, 同样按成功处理
  Future<CloudPushResult> _deleteCloudRow(int serverId, int localId) async {
    try {
      await _api.deleteWish(serverId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return CloudPushResult.unauthorized;
      if (e.response?.statusCode != 404) {
        debugPrint('云端删除失败 serverId=$serverId: $e');
        return CloudPushResult.failed;
      }
    } catch (e) {
      debugPrint('云端删除失败 serverId=$serverId: $e');
      return CloudPushResult.failed;
    }

    await DBUtils.db.delete(
      WishTable.name,
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
    );
    return CloudPushResult.success;
  }

  /// 本地删除后立刻试删云端, 失败保留墓碑等下次同步
  /// 网络抖一下就失败的话另一台设备会一直看到这条心愿, 这里多试一次
  Future<CloudPushResult> tryPushDeleted(int localId) async {
    final maps = await DBUtils.db.query(
      WishTable.name,
      columns: [WishTable.colServerId],
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
      limit: 1,
    );
    // 没上过云的已经直接物理删掉了, 没有云端要处理
    if (maps.isEmpty) return CloudPushResult.success;

    final serverId = maps.first[WishTable.colServerId] as int?;
    if (serverId == null) return CloudPushResult.success;

    final first = await _deleteCloudRow(serverId, localId);
    if (first == CloudPushResult.success) return first;
    return _deleteCloudRow(serverId, localId);
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
      await pushNewWish(localWish);
    }
  }

  /// 把一条还没上云的心愿推上去, 成功后回填 serverId
  /// 失败就留在本地, 等下次同步再试
  Future<bool> pushNewWish(WishModel localWish) async {
    if (localWish.localId == null || localWish.serverId != null) return false;
    if (localWish.storageMode == StorageMode.local) return false;
    if (localWish.ownerUsername == null || localWish.ownerUsername!.isEmpty) {
      return false;
    }

    final db = DBUtils.db;
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

      // 创建时已经把当前内容传上去了, 内容和可见性没再变的话可以顺便清脏
      await db.update(
        WishTable.name,
        {WishTable.colContentDirty: 0},
        where: '''
          ${WishTable.colLocalId} = ?
          AND ${WishTable.colContent} = ?
          AND ${WishTable.colVisibility} = ?
        ''',
        whereArgs: [localWish.localId, localWish.content, localWish.visibility.value],
      );
      // 自己选的云端存储也算确认过, 退出登录再拉回来时不再询问
      if (localWish.storageMode == StorageMode.cloud) {
        await CloudKeepIds.add(localWish.ownerUsername, [serverId]);
      }
      debugPrint('新建心愿已上云 localId=${localWish.localId} serverId=$serverId');
      return true;
    } catch (e) {
      debugPrint('推送新建心愿失败 localId=${localWish.localId}: $e');
      return false;
    }
  }

  /// 只推送本地改过的状态
  Future<void> pushUpdatedStatus(String currentUsername) async {
    final db = DBUtils.db;
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
        AND ${WishTable.colStatusDirty} = 1
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [StorageMode.local.value, currentUsername],
    );
    debugPrint('待推送状态修改 ${maps.length} 条');

    for (var map in maps) {
      final localWish = WishModel.fromMap(map);
      try {
        await pushWishStatus(localWish);
      } catch (e) {
        debugPrint('推送状态失败 localId=${localWish.localId}: $e');
      }
    }
  }

  /// 立即推送单条状态, 成功后清掉脏标记
  Future<void> pushWishStatus(WishModel wish) async {
    await _api.updateWishStatus(wish.serverId!, wish.status);
    debugPrint('状态已推送 localId=${wish.localId} serverId=${wish.serverId}');

    final localId = wish.localId;
    if (localId == null) return;

    // 推送期间用户可能又改了, 状态还对得上才清标记
    await DBUtils.db.update(
      WishTable.name,
      {WishTable.colStatusDirty: 0},
      where: '${WishTable.colLocalId} = ? AND ${WishTable.colStatus} = ?',
      whereArgs: [localId, wish.status],
    );
  }

  /// 本地改完状态立刻试推一次, 失败保留脏标记
  /// 界面根据返回值提示用户, 登录失效单独走全局弹窗
  Future<CloudPushResult> tryPushStatus(WishModel wish) async {
    if (wish.serverId == null || wish.storageMode == StorageMode.local) {
      return CloudPushResult.success;
    }
    try {
      await pushWishStatus(wish);
      return CloudPushResult.success;
    } on DioException catch (e) {
      debugPrint('立即推送状态失败 serverId=${wish.serverId}: $e');
      return e.response?.statusCode == 401
          ? CloudPushResult.unauthorized
          : CloudPushResult.failed;
    } catch (e) {
      debugPrint('立即推送状态失败 serverId=${wish.serverId}: $e');
      return CloudPushResult.failed;
    }
  }

  /// 只推送本地改过的内容/可见性
  Future<void> pushUpdatedWishes(String currentUsername) async {
    final db = DBUtils.db;
    final maps = await db.query(
      WishTable.name,
      where: '''
        ${WishTable.colServerId} IS NOT NULL 
        AND ${WishTable.colIsDeleted} = 0 
        AND ${WishTable.colStorageMode} != ?
        AND ${WishTable.colContentDirty} = 1
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [StorageMode.local.value, currentUsername],
    );
    debugPrint('待推送内容修改 ${maps.length} 条');

    for (var map in maps) {
      final localWish = WishModel.fromMap(map);
      // 公开、私有都推送: 公开心愿需要登录作者才能修改, 改完要覆盖云端
      try {
        await pushWishContent(localWish);
      } catch (e) {
        debugPrint('推送修改心愿失败 localId=${localWish.localId}: $e');
      }
    }
  }

  /// 立即推送单条内容/可见性, 成功后清掉脏标记
  Future<void> pushWishContent(WishModel wish) async {
    await _api.updateWish(wish.serverId!, wish.content, wish.visibility.value);
    debugPrint('内容已推送 localId=${wish.localId} serverId=${wish.serverId}');

    final localId = wish.localId;
    if (localId == null) return;

    // 推送期间用户可能又改了, 内容和可见性还对得上才清标记
    await DBUtils.db.update(
      WishTable.name,
      {WishTable.colContentDirty: 0},
      where: '''
        ${WishTable.colLocalId} = ?
        AND ${WishTable.colContent} = ?
        AND ${WishTable.colVisibility} = ?
      ''',
      whereArgs: [localId, wish.content, wish.visibility.value],
    );
  }

  /// 完整的云端同步流程
  /// 返回这次从云端新拉到本地的心愿
  Future<List<WishModel>> syncAll(String? currentUsername) async {
    if (currentUsername == null || currentUsername.isEmpty) {
      debugPrint('未登录, 跳过云端同步');
      return const [];
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
      final newWishes = await pullMyWishes(currentUsername);
      
      debugPrint('--- 同步完成 ---');
      return newWishes;
    } catch (e) {
      debugPrint('同步过程中发生错误: $e');
      rethrow; // 抛给 UI 层去弹窗提示
    }
  }

  /// 更新本地心愿数据(云端回写/缓存刷新用), 不改脏标记
  Future<void> updateWishLocal(WishModel wish) async {
    final db = DBUtils.db;
    await db.update(
      WishTable.name,
      wish.toMap(),
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [wish.localId],
    );
  }

  /// 本地编辑内容/可见性, 标脏
  Future<void> updateWishContent(WishModel wish) async {
    final db = DBUtils.db;
    debugPrint('本地修改内容 localId=${wish.localId} 可见性=${wish.visibility.value}');
    await db.update(
      WishTable.name,
      {
        WishTable.colContent: wish.content,
        WishTable.colVisibility: wish.visibility.value,
        WishTable.colCategory: wish.category.name,
        WishTable.colContentDirty: 1,
      },
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [wish.localId],
    );
  }

  /// 本地切换状态, 标脏
  Future<void> updateWishStatus(WishModel wish) async {
    final db = DBUtils.db;
    debugPrint('本地修改状态 localId=${wish.localId} 状态=${wish.status}');
    await db.update(
      WishTable.name,
      {
        WishTable.colStatus: wish.status,
        WishTable.colStatusDirty: 1,
      },
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [wish.localId],
    );
  }

  /// 修改本地心愿的存储模式(只改本地, 不参与云端同步)
  Future<void> updateWishStorageMode(List<int> localIds, StorageMode mode) async {
    if (localIds.isEmpty) return;
    final db = DBUtils.db;

    for (final localId in localIds) {
      await db.update(
        WishTable.name,
        {WishTable.colStorageMode: mode.value},
        where: '${WishTable.colLocalId} = ?',
        whereArgs: [localId],
      );
    }

    debugPrint('修改存储模式 ${mode.value}, 共 ${localIds.length} 条');
  }

  /// 只更新评论, 不动脏标记
  Future<void> updateWishComments(WishModel wish) async {
    final db = DBUtils.db;
    await db.update(
      WishTable.name,
      {
        WishTable.colComments: jsonEncode(wish.comments.map((e) => e.toJson()).toList()),
      },
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [wish.localId],
    );
  }

  /// 当前账号在本地还存在的云端心愿 serverId
  /// 用来清理"已确认保持云端"里已经失效的记录
  Future<Set<int>> getLocalServerIds(String username) async {
    final db = DBUtils.db;
    final maps = await db.query(
      WishTable.name,
      columns: [WishTable.colServerId],
      where: '''
        ${WishTable.colServerId} IS NOT NULL
        AND ${WishTable.colIsDeleted} = 0
        AND ${WishTable.colIsPublicCache} = 0
        AND ${WishTable.colOwnerUsername} = ?
      ''',
      whereArgs: [username],
    );

    return maps
        .map((e) => e[WishTable.colServerId] as int)
        .toSet();
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