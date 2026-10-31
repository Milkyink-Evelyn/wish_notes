import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wish_notes/models/wish_model.dart';
import 'package:wish_notes/repositories/wish_repository.dart';
import 'package:wish_notes/utils/cloud_keep_ids.dart';
import 'package:wish_notes/utils/db_utils.dart';
import 'package:wish_notes/utils/sp_utils.dart';
import 'package:wish_notes/utils/wish_api.dart';

/// 造一条测试心愿, 只关心和同步相关的字段
WishModel buildWish({
  required String content,
  required WishVisibility visibility,
  required StorageMode storageMode,
  int? serverId,
  String status = WishStatus.unrealized,
  WishCategory category = WishCategory.other,
  String? ownerUsername,
  bool isDeleted = false,
  bool isPublicCache = false,
  bool contentDirty = false,
  bool statusDirty = false,
  int createdAt = 1700000000000,
}) {
  return WishModel(
    serverId: serverId,
    content: content,
    visibility: visibility,
    status: status,
    storageMode: storageMode,
    createdAt: createdAt,
    isDeleted: isDeleted,
    category: category,
    ownerUsername: ownerUsername,
    isPublicCache: isPublicCache,
    contentDirty: contentDirty,
    statusDirty: statusDirty,
  );
}

/// 只返回预先准备好的数据, 测试同步逻辑时不碰网络
/// 推送接口会同步改掉 myWishes 里的数据, 模拟服务器被更新
class FakeWishApi extends WishApi {
  List<Map<String, dynamic>> myWishes = [];
  int updateWishCalls = 0;
  int updateStatusCalls = 0;
  bool failUpdateWish = false;
  bool failUpdateStatus = false;

  @override
  Future<List<Map<String, dynamic>>> fetchMyWishes() async => myWishes;

  @override
  Future<void> updateWish(int serverId, String content, String visibility) async {
    updateWishCalls++;
    if (failUpdateWish) throw Exception('updateWish failed');
    for (final wish in myWishes) {
      if (wish['id'] == serverId) {
        wish['content'] = content;
        wish['visibility'] = visibility;
      }
    }
  }

  @override
  Future<void> updateWishStatus(int serverId, String status) async {
    updateStatusCalls++;
    if (failUpdateStatus) throw Exception('updateWishStatus failed');
    for (final wish in myWishes) {
      if (wish['id'] == serverId) {
        wish['status'] = status;
      }
    }
  }
}

/// 模拟云端服务器, 两台设备共用同一份数据
class FakeCloudServer {
  final List<Map<String, dynamic>> wishes = [];
  int _nextId = 1;
  bool failCreate = false;
  bool failDelete = false;

  Map<String, dynamic> create({
    required String content,
    required String visibility,
    required String username,
  }) {
    final wish = <String, dynamic>{
      'id': _nextId++,
      'content': content,
      'visibility': visibility,
      'status': WishStatus.unrealized,
      'createdAt': DateTime.now().toIso8601String(),
      'username': username,
      'comments': <Map<String, dynamic>>[],
    };
    wishes.add(wish);
    return wish;
  }
}

/// 一台设备访问云端用的接口, 所有设备操作同一个 FakeCloudServer
class FakeCloudApi extends WishApi {
  final FakeCloudServer server;
  final String username;

  FakeCloudApi(this.server, this.username);

  @override
  Future<List<Map<String, dynamic>>> fetchMyWishes() async {
    return server.wishes
        .where((e) => e['username'] == username)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPublicWishes() async {
    return server.wishes
        .where((e) => e['visibility'] == WishVisibility.public.value)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createWish(String content, String visibility) async {
    if (server.failCreate) throw Exception('create failed');
    return Map<String, dynamic>.from(
      server.create(content: content, visibility: visibility, username: username),
    );
  }

  @override
  Future<void> updateWish(int serverId, String content, String visibility) async {
    final wish = server.wishes.firstWhere((e) => e['id'] == serverId);
    wish['content'] = content;
    wish['visibility'] = visibility;
  }

  @override
  Future<void> updateWishStatus(int serverId, String status) async {
    final wish = server.wishes.firstWhere((e) => e['id'] == serverId);
    wish['status'] = status;
  }

  @override
  Future<void> deleteWish(int serverId) async {
    if (server.failDelete) throw Exception('delete failed');
    server.wishes.removeWhere((e) => e['id'] == serverId);
  }
}

/// 删除时云端记录已经不存在, 返回 404
class NotFoundDeleteApi extends FakeCloudApi {
  NotFoundDeleteApi(super.server, super.username);

  @override
  Future<void> deleteWish(int serverId) async {
    final options = RequestOptions(path: '/wishes/$serverId');
    throw DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 404),
    );
  }
}

/// 每条用例开一个全新的内存数据库
Future<Database> openTestDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      // 每次开一个新的内存库, 模拟两台设备时不共用同一份数据
      singleInstance: false,
      onCreate: (db, version) => DBUtils.createTables(db),
    ),
  );
  DBUtils.useTestDatabase(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late WishRepository repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    await SPUtils.init();
  });

  setUp(() async {
    // 清掉上一条用例留下的确认记录
    await SPUtils.remove(SPKey.cloudKeepIds);

    db = await openTestDb();
    repo = WishRepository(api: FakeWishApi());
  });

  tearDown(() async {
    await db.close();
  });

  group('退出登录清理', () {
    test('删除所有云端存储的心愿, 保留智能/本地/缓存/墓碑', () async {
      await repo.insertWish(buildWish(
        content: 'cloud public',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        serverId: 1,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'cloud private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        serverId: 2,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'smart public',
        visibility: WishVisibility.public,
        storageMode: StorageMode.smart,
        serverId: 3,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'smart private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 4,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'local private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.local,
      ));
      await repo.insertWish(buildWish(
        content: 'square cache',
        visibility: WishVisibility.public,
        storageMode: StorageMode.smart,
        serverId: 5,
        ownerUsername: 'bob',
        isPublicCache: true,
      ));
      await repo.insertWish(buildWish(
        content: 'cloud public tombstone',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        serverId: 6,
        ownerUsername: 'alice',
        isDeleted: true,
      ));
      await repo.insertWish(buildWish(
        content: 'cloud public unsynced',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      ));

      await repo.clearCloudWishes();

      final rows = await db.query(WishTable.name);
      final contents = rows.map((e) => e[WishTable.colContent]).toSet();
      expect(contents, isNot(contains('cloud public')));
      expect(contents, isNot(contains('cloud private')));
      expect(contents, containsAll([
        'smart public',
        'smart private',
        'local private',
        'square cache',
        'cloud public tombstone',
        'cloud public unsynced',
      ]));
    });

    test('清理后游客列表不再看到云端心愿', () async {
      await repo.insertWish(buildWish(
        content: 'cloud public',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        serverId: 1,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'cloud private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        serverId: 2,
        ownerUsername: 'alice',
      ));
      await repo.insertWish(buildWish(
        content: 'smart public',
        visibility: WishVisibility.public,
        storageMode: StorageMode.smart,
        serverId: 3,
        ownerUsername: 'alice',
      ));

      await repo.clearCloudWishes();
      final visible = await repo.getMyWishes();

      expect(visible.map((w) => w.content), isNot(contains('cloud public')));
      expect(visible.map((w) => w.content), isNot(contains('cloud private')));
      expect(visible.map((w) => w.content), contains('smart public'));
    });
  });

  group('删除心愿', () {
    test('没上过云的心愿直接物理删除', () async {
      final id = await repo.insertWish(buildWish(
        content: 'local only',
        visibility: WishVisibility.private,
        storageMode: StorageMode.local,
      ));

      await repo.deleteWish(id);

      expect(await db.query(WishTable.name), isEmpty);
    });

    test('没上传成功的云端心愿也直接物理删除', () async {
      final id = await repo.insertWish(buildWish(
        content: 'cloud unsynced',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
      ));

      await repo.deleteWish(id);

      expect(await db.query(WishTable.name), isEmpty);
    });

    test('上过云的心愿打墓碑', () async {
      final id = await repo.insertWish(buildWish(
        content: 'synced',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        serverId: 1,
        ownerUsername: 'alice',
      ));

      await repo.deleteWish(id);

      final row = (await db.query(WishTable.name)).single;
      expect(row[WishTable.colIsDeleted], 1);
    });

    test('没上过云的心愿删除后没有云端要处理', () async {
      final id = await repo.insertWish(buildWish(
        content: 'local only',
        visibility: WishVisibility.private,
        storageMode: StorageMode.local,
      ));

      await repo.deleteWish(id);

      // 本地已物理删除, 不能再当成云端删除失败提示用户
      expect(await repo.tryPushDeleted(id), CloudPushResult.success);
    });
  });

  group('云端同步', () {
    test('公开心愿拉取时保留本地分类', () async {
      await repo.insertWish(buildWish(
        content: 'old content',
        visibility: WishVisibility.public,
        storageMode: StorageMode.smart,
        serverId: 42,
        category: WishCategory.travel,
        ownerUsername: 'alice',
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 42,
            'content': 'new content',
            'visibility': 'PUBLIC',
            'status': 'REALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      final wish = WishModel.fromMap(row);
      expect(wish.content, 'new content');
      expect(wish.status, WishStatus.realized);
      expect(wish.category, WishCategory.travel);
      expect(wish.storageMode, StorageMode.smart); // 拉取不能把智能存储改成云端
    });

    test('广场缓存转成自己的公开心愿时保留分类', () async {
      await repo.insertWish(buildWish(
        content: 'cached content',
        visibility: WishVisibility.public,
        storageMode: StorageMode.smart,
        serverId: 43,
        category: WishCategory.hobby,
        isPublicCache: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 43,
            'content': 'cached content',
            'visibility': 'PUBLIC',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      final wish = WishModel.fromMap(row);
      expect(row[WishTable.colIsPublicCache], 0);
      expect(wish.ownerUsername, 'alice');
      expect(wish.category, WishCategory.hobby);
      expect(wish.storageMode, StorageMode.cloud); // 本地没有正本, 转正后算云端专属
    });

    test('私有智能心愿有本地修改时以本地为准', () async {
      await repo.insertWish(buildWish(
        content: 'local private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 44,
        category: WishCategory.study,
        ownerUsername: 'alice',
        contentDirty: true,
        statusDirty: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 44,
            'content': 'cloud content',
            'visibility': 'PRIVATE',
            'status': 'REALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      final wish = WishModel.fromMap(row);
      expect(wish.content, 'local private');
      expect(wish.status, WishStatus.unrealized);
      expect(wish.category, WishCategory.study);
      expect(wish.storageMode, StorageMode.smart);
    });

    test('私有智能心愿没有本地修改时接受云端', () async {
      await repo.insertWish(buildWish(
        content: 'local old',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 48,
        category: WishCategory.study,
        ownerUsername: 'alice',
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 48,
            'content': 'cloud new',
            'visibility': 'PRIVATE',
            'status': 'REALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.content, 'cloud new');
      expect(wish.status, WishStatus.realized);
      expect(wish.category, WishCategory.study);
      expect(wish.storageMode, StorageMode.smart);
    });

    test('私有云端心愿以服务器为准', () async {
      await repo.insertWish(buildWish(
        content: 'local old',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        serverId: 45,
        category: WishCategory.life,
        ownerUsername: 'alice',
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 45,
            'content': 'cloud new',
            'visibility': 'PRIVATE',
            'status': 'REALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      final wish = WishModel.fromMap(row);
      expect(wish.content, 'cloud new');
      expect(wish.status, WishStatus.realized);
      expect(wish.category, WishCategory.life);
      expect(wish.storageMode, StorageMode.cloud);
    });

    test('本地没有的云端心愿拉下来记为云端专属, 退出时能清掉', () async {
      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 46,
            'content': 'cloud only',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      expect(WishModel.fromMap(row).storageMode, StorageMode.cloud);

      await repo.clearCloudWishes();
      expect(await db.query(WishTable.name), isEmpty);
    });

    test('新拉下来的云端心愿可以改成智能存储, 退出时保留', () async {
      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 60,
            'content': 'cloud only 1',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
          {
            'id': 61,
            'content': 'cloud only 2',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T09:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      final pullRepo = WishRepository(api: api);
      final newWishes = await pullRepo.pullMyWishes('alice');

      expect(newWishes.length, 2);
      expect(newWishes.every((w) => w.localId != null), isTrue);
      expect(newWishes.every((w) => w.storageMode == StorageMode.cloud), isTrue);

      // 只把其中一条改成智能, 另一条保持云端
      final smartId = newWishes.first.localId!;
      await pullRepo.updateWishStorageMode([smartId], StorageMode.smart);

      await pullRepo.clearCloudWishes();

      final remaining = (await db.query(WishTable.name)).single;
      expect(remaining[WishTable.colLocalId], smartId);
      expect(remaining[WishTable.colStorageMode], StorageMode.smart.value);
    });

    test('云端存储的公开心愿拉取后仍保持云端存储', () async {
      await repo.insertWish(buildWish(
        content: 'old content',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        serverId: 47,
        ownerUsername: 'alice',
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 47,
            'content': 'new content',
            'visibility': 'PUBLIC',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final row = (await db.query(WishTable.name)).single;
      final wish = WishModel.fromMap(row);
      expect(wish.content, 'new content');
      expect(wish.storageMode, StorageMode.cloud);

      await repo.clearCloudWishes();
      expect(await db.query(WishTable.name), isEmpty);
    });
  });

  group('脏标记同步', () {
    test('只推内容, 不推状态', () async {
      await repo.insertWish(buildWish(
        content: 'local edit',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 50,
        ownerUsername: 'alice',
        contentDirty: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 50,
            'content': 'cloud old',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      final dirtyRepo = WishRepository(api: api);
      await dirtyRepo.pushUpdatedWishes('alice');
      await dirtyRepo.pushUpdatedStatus('alice');

      expect(api.updateWishCalls, 1);
      expect(api.updateStatusCalls, 0);

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.content, 'local edit');
      expect(wish.contentDirty, isFalse);
      expect(wish.statusDirty, isFalse);
    });

    test('只推状态, 不推内容', () async {
      await repo.insertWish(buildWish(
        content: 'same content',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 51,
        status: WishStatus.realized,
        ownerUsername: 'alice',
        statusDirty: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 51,
            'content': 'same content',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      final dirtyRepo = WishRepository(api: api);
      await dirtyRepo.pushUpdatedWishes('alice');
      await dirtyRepo.pushUpdatedStatus('alice');

      expect(api.updateWishCalls, 0);
      expect(api.updateStatusCalls, 1);

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.status, WishStatus.realized);
      expect(wish.statusDirty, isFalse);
    });

    test('推送失败时保留脏标记', () async {
      await repo.insertWish(buildWish(
        content: 'local edit',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 52,
        status: WishStatus.realized,
        ownerUsername: 'alice',
        contentDirty: true,
        statusDirty: true,
      ));

      final api = FakeWishApi()
        ..failUpdateWish = true
        ..failUpdateStatus = true;

      final dirtyRepo = WishRepository(api: api);
      await dirtyRepo.pushUpdatedWishes('alice');
      await dirtyRepo.pushUpdatedStatus('alice');

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.contentDirty, isTrue);
      expect(wish.statusDirty, isTrue);
    });

    test('拉取时脏字段保留本地, 干净字段接受云端', () async {
      await repo.insertWish(buildWish(
        content: 'local edit',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 53,
        ownerUsername: 'alice',
        contentDirty: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 53,
            'content': 'cloud content',
            'visibility': 'PRIVATE',
            'status': 'REALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).pullMyWishes('alice');

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.content, 'local edit'); // 内容有本地修改, 不被覆盖
      expect(wish.contentDirty, isTrue);
      expect(wish.status, WishStatus.realized); // 状态没改过, 跟随云端
      expect(wish.statusDirty, isFalse);
    });

    test('完整同步把本地修改推上去', () async {
      await repo.insertWish(buildWish(
        content: 'local edit',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 54,
        status: WishStatus.realized,
        ownerUsername: 'alice',
        contentDirty: true,
        statusDirty: true,
      ));

      final api = FakeWishApi()
        ..myWishes = [
          {
            'id': 54,
            'content': 'cloud old',
            'visibility': 'PRIVATE',
            'status': 'UNREALIZED',
            'createdAt': '2026-10-30T10:00:00.000Z',
            'username': 'alice',
            'comments': [],
          },
        ];

      await WishRepository(api: api).syncAll('alice');

      expect(api.updateWishCalls, 1);
      expect(api.updateStatusCalls, 1);

      final wish = WishModel.fromMap((await db.query(WishTable.name)).single);
      expect(wish.content, 'local edit');
      expect(wish.status, WishStatus.realized);
      expect(wish.contentDirty, isFalse);
      expect(wish.statusDirty, isFalse);
    });
  });

  group('数据库升级', () {
    test('v3 升级到 v4 补齐脏标记, 智能存储的已同步心愿标脏', () async {
      // 内存库和 setUp 里那条连接会共用, 这里用临时文件单独开一个
      final tempDir = await Directory.systemTemp.createTemp('wish_notes_test_');
      Database? openedDb;

      try {
        final v3db = await databaseFactory.openDatabase(
          p.join(tempDir.path, 'v3.db'),
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE ${WishTable.name} (
                  ${WishTable.colLocalId} INTEGER PRIMARY KEY AUTOINCREMENT,
                  ${WishTable.colServerId} INTEGER,
                  ${WishTable.colContent} TEXT NOT NULL,
                  ${WishTable.colVisibility} TEXT NOT NULL,
                  ${WishTable.colStatus} TEXT NOT NULL,
                  ${WishTable.colStorageMode} TEXT NOT NULL,
                  ${WishTable.colCreatedAt} INTEGER NOT NULL,
                  ${WishTable.colIsDeleted} INTEGER NOT NULL DEFAULT 0,
                  ${WishTable.colCategory} TEXT,
                  ${WishTable.colComments} TEXT,
                  ${WishTable.colOwnerUsername} TEXT,
                  ${WishTable.colIsPublicCache} INTEGER NOT NULL DEFAULT 0
                )
              ''');
            },
          ),
        );
        openedDb = v3db;

        Future<void> insertRow(
          String content,
          int? serverId,
          StorageMode mode, {
          int isDeleted = 0,
        }) async {
          await v3db.insert(WishTable.name, {
            WishTable.colServerId: serverId,
            WishTable.colContent: content,
            WishTable.colVisibility: WishVisibility.private.value,
            WishTable.colStatus: WishStatus.unrealized,
            WishTable.colStorageMode: mode.value,
            WishTable.colCreatedAt: 1700000000000,
            WishTable.colIsDeleted: isDeleted,
          });
        }

        await insertRow('smart synced', 1, StorageMode.smart);
        await insertRow('cloud synced', 2, StorageMode.cloud);
        await insertRow('local only', null, StorageMode.local);
        await insertRow('smart tombstone', 3, StorageMode.smart, isDeleted: 1);
        await insertRow('smart unsynced', null, StorageMode.smart);

        await DBUtils.upgradeTables(v3db, 3, 4);

        final rows = await v3db.query(WishTable.name);
        final byContent = {
          for (final row in rows) row[WishTable.colContent] as String: row,
        };

        expect(byContent['smart synced']![WishTable.colContentDirty], 1);
        expect(byContent['smart synced']![WishTable.colStatusDirty], 1);
        expect(byContent['cloud synced']![WishTable.colContentDirty], 0);
        expect(byContent['cloud synced']![WishTable.colStatusDirty], 0);
        expect(byContent['local only']![WishTable.colContentDirty], 0);
        expect(byContent['smart tombstone']![WishTable.colContentDirty], 0);
        expect(byContent['smart unsynced']![WishTable.colContentDirty], 0);
      } finally {
        await openedDb?.close();
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('两台设备同步', () {
    test('A 新建云端私有心愿, B 同步能收到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: 'A 的私有云端心愿',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      final pushed = await repoA.pushNewWish(wish.copyWith(localId: localId));
      expect(pushed, isTrue);
      expect(server.wishes, hasLength(1));

      // A 本地回填 serverId 并清掉脏标记
      final rowA = (await db.query(WishTable.name)).single;
      expect(rowA[WishTable.colServerId], 1);
      expect(rowA[WishTable.colContentDirty], 0);
      // 自己创建的云端心愿也记进确认集合, 重新登录不再询问
      expect(CloudKeepIds.read('alice'), contains(1));

      // 换一台设备, 同步云端
      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      final rows = await deviceB.query(WishTable.name);
      expect(rows, hasLength(1));

      final pulled = WishModel.fromMap(rows.single);
      expect(pulled.content, 'A 的私有云端心愿');
      expect(pulled.visibility, WishVisibility.private);
      expect(pulled.storageMode, StorageMode.cloud);
      expect(pulled.isPublicCache, isFalse);
      expect(pulled.ownerUsername, 'alice');
      expect(pulled.serverId, 1);
    });

    test('A 新建智能私有心愿, B 同步也能收到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: 'A 的私有智能心愿',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      expect(await repoA.pushNewWish(wish.copyWith(localId: localId)), isTrue);

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      final rows = await deviceB.query(WishTable.name);
      expect(rows, hasLength(1));
      final pulled = WishModel.fromMap(rows.single);
      expect(pulled.content, 'A 的私有智能心愿');
      expect(pulled.visibility, WishVisibility.private);
      // 本地没有的云端心愿, B 侧默认按云端存放
      expect(pulled.storageMode, StorageMode.cloud);
    });

    test('A 新建纯本地心愿不会上传, B 也看不到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '只在 A 本地',
        visibility: WishVisibility.private,
        storageMode: StorageMode.local,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      expect(await repoA.pushNewWish(wish.copyWith(localId: localId)), isFalse);
      expect(server.wishes, isEmpty);

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      expect(await deviceB.query(WishTable.name), isEmpty);
    });

    test('A 上传失败时 B 收不到, A 下次同步补推后 B 能收到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '断网时创建',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );

      server.failCreate = true;
      final localId = await repoA.insertWish(wish);
      expect(await repoA.pushNewWish(wish.copyWith(localId: localId)), isFalse);
      expect(server.wishes, isEmpty);

      // A 下次同步补推
      server.failCreate = false;
      await repoA.syncAll('alice');
      expect(server.wishes, hasLength(1));

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      final rows = await deviceB.query(WishTable.name);
      expect(rows, hasLength(1));
      expect(WishModel.fromMap(rows.single).content, '断网时创建');
    });

    test('A 修改状态后 B 同步能看到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '状态同步',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localId));

      final synced = wish.copyWith(localId: localId, serverId: 1);
      final updated = synced.copyWith(
        status: WishStatus.realized,
        statusDirty: true,
      );
      await repoA.updateWishStatus(updated);
      await repoA.tryPushStatus(updated);
      expect(server.wishes.single['status'], WishStatus.realized);

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      final pulled = WishModel.fromMap(
        (await deviceB.query(WishTable.name)).single,
      );
      expect(pulled.status, WishStatus.realized);
    });

    test('A 修改内容后 B 同步能看到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '修改前',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localId));

      final synced = wish.copyWith(localId: localId, serverId: 1);
      final updated = synced.copyWith(
        content: '修改后',
        contentDirty: true,
      );
      await repoA.updateWishContent(updated);
      await repoA.pushWishContent(updated);
      expect(server.wishes.single['content'], '修改后');

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');

      final pulled = WishModel.fromMap(
        (await deviceB.query(WishTable.name)).single,
      );
      expect(pulled.content, '修改后');
    });

    test('A 删除后 B 同步会把本地副本删掉', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '删除同步',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );

      final localId = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localId));

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');
      expect(await deviceB.query(WishTable.name), hasLength(1));

      // 切回 A 删除, 并立刻同步到云端
      DBUtils.useTestDatabase(db);
      await repoA.deleteWish(localId);
      await repoA.tryPushDeleted(localId);
      expect(server.wishes, isEmpty);

      // B 再同步, 本地副本被僵尸清理删掉
      DBUtils.useTestDatabase(deviceB);
      await repoB.syncAll('alice');
      expect(await deviceB.query(WishTable.name), isEmpty);
    });

    test('B 导入云端心愿后删除, A 同步也会删掉本地副本', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: 'B 导入后删除',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localIdA = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localIdA));

      // B 同步导入这条心愿
      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');
      final wishB = WishModel.fromMap(
        (await deviceB.query(WishTable.name)).single,
      );

      // 导入时选了智能存储, 再删除
      await repoB.updateWishStorageMode([wishB.localId!], StorageMode.smart);
      await repoB.deleteWish(wishB.localId!);
      await repoB.tryPushDeleted(wishB.localId!);
      expect(server.wishes, isEmpty);

      // A 再同步, 本地副本应该跟着消失
      DBUtils.useTestDatabase(db);
      await repoA.syncAll('alice');
      expect(await db.query(WishTable.name), isEmpty);
    });

    test('B 删除时云端失败, 下次同步补删后 A 也会消失', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: 'B 离线删除',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localIdA = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localIdA));

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');
      final wishB = WishModel.fromMap(
        (await deviceB.query(WishTable.name)).single,
      );

      // 删除时网络失败, 墓碑留在本地
      server.failDelete = true;
      await repoB.deleteWish(wishB.localId!);
      expect(
        await repoB.tryPushDeleted(wishB.localId!),
        CloudPushResult.failed,
      );
      expect(server.wishes, hasLength(1));
      final tombstone = (await deviceB.query(WishTable.name)).single;
      expect(tombstone[WishTable.colIsDeleted], 1);

      // 恢复网络后, B 下次同步补删云端
      server.failDelete = false;
      await repoB.syncAll('alice');
      expect(server.wishes, isEmpty);
      expect(await deviceB.query(WishTable.name), isEmpty);

      // A 同步后本地副本消失
      DBUtils.useTestDatabase(db);
      await repoA.syncAll('alice');
      expect(await db.query(WishTable.name), isEmpty);
    });

    test('云端记录本来就不存在时, 删除按成功处理', () async {
      await repo.insertWish(buildWish(
        content: '云端已不存在',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        serverId: 99,
        ownerUsername: 'alice',
        isDeleted: true,
      ));

      final api = NotFoundDeleteApi(FakeCloudServer(), 'alice');
      await WishRepository(api: api).syncAll('alice');

      expect(await db.query(WishTable.name), isEmpty);
    });

    test('A 新建公开云端心愿, B 的广场刷新能看到', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: 'A 的公开云端心愿',
        visibility: WishVisibility.public,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localId = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localId));

      // B 是另一个账号, 在广场里应该看到这条公开心愿
      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'bob'));
      await repoB.refreshPublicWishes('bob');

      final rows = await deviceB.query(WishTable.name);
      expect(rows, hasLength(1));
      final cached = WishModel.fromMap(rows.single);
      expect(cached.content, 'A 的公开云端心愿');
      expect(cached.isPublicCache, isTrue);
      expect(cached.ownerUsername, 'alice');
    });

    test('两台设备各自新建, 同步后都能看到两条', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wishA = buildWish(
        content: 'A 写的心愿',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localIdA = await repoA.insertWish(wishA);
      await repoA.pushNewWish(wishA.copyWith(localId: localIdA));

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wishB = buildWish(
        content: 'B 写的心愿',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localIdB = await repoB.insertWish(wishB);
      await repoB.pushNewWish(wishB.copyWith(localId: localIdB));
      expect(server.wishes, hasLength(2));

      await repoB.syncAll('alice');
      final rowsB = await deviceB.query(WishTable.name);
      expect(rowsB, hasLength(2));

      DBUtils.useTestDatabase(db);
      await repoA.syncAll('alice');
      final rowsA = await db.query(WishTable.name);
      expect(rowsA, hasLength(2));
    });

    test('B 重复同步不会插入重复记录', () async {
      final server = FakeCloudServer();
      final repoA = WishRepository(api: FakeCloudApi(server, 'alice'));
      final wish = buildWish(
        content: '只应有一条',
        visibility: WishVisibility.private,
        storageMode: StorageMode.cloud,
        ownerUsername: 'alice',
      );
      final localId = await repoA.insertWish(wish);
      await repoA.pushNewWish(wish.copyWith(localId: localId));

      final deviceB = await openTestDb();
      addTearDown(() => deviceB.close());
      final repoB = WishRepository(api: FakeCloudApi(server, 'alice'));
      await repoB.syncAll('alice');
      await repoB.syncAll('alice');

      expect(await deviceB.query(WishTable.name), hasLength(1));
    });
  });

  group('确认集合通知', () {
    test('添加和清空都会通知界面刷新', () async {
      var notified = 0;
      void listener() => notified++;
      CloudKeepIds.changes.addListener(listener);
      addTearDown(() => CloudKeepIds.changes.removeListener(listener));

      await CloudKeepIds.add('alice', [1]);
      expect(notified, 1);
      expect(CloudKeepIds.count('alice'), 1);

      await CloudKeepIds.clear('alice');
      expect(notified, 2);
      expect(CloudKeepIds.count('alice'), 0);

      await CloudKeepIds.clearAll();
      expect(notified, 3);
    });
  });
}
