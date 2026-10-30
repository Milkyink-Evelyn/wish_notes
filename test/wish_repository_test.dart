import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wish_notes/models/wish_model.dart';
import 'package:wish_notes/repositories/wish_repository.dart';
import 'package:wish_notes/utils/db_utils.dart';
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

/// 每条用例开一个全新的内存数据库
Future<Database> openTestDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
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
}
