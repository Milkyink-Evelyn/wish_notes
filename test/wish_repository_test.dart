import 'package:flutter_test/flutter_test.dart';
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
  );
}

/// 只返回预先准备好的数据, 测试同步逻辑时不碰网络
class FakeWishApi extends WishApi {
  List<Map<String, dynamic>> myWishes = [];

  @override
  Future<List<Map<String, dynamic>>> fetchMyWishes() async => myWishes;
}

/// 每条用例开一个全新的内存数据库
Future<Database> openTestDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
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

    test('私有智能心愿以本地为准, 不被云端覆盖', () async {
      await repo.insertWish(buildWish(
        content: 'local private',
        visibility: WishVisibility.private,
        storageMode: StorageMode.smart,
        serverId: 44,
        category: WishCategory.study,
        ownerUsername: 'alice',
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
}
