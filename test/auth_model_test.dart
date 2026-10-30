import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wish_notes/logic/auth_model.dart';
import 'package:wish_notes/models/wish_model.dart';
import 'package:wish_notes/repositories/wish_repository.dart';
import 'package:wish_notes/utils/db_utils.dart';
import 'package:wish_notes/utils/sp_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('退出登录会清掉云端心愿(公开和私有), 保留智能存储心愿', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
      'auth_token': 'fake-token',
      'user_info': '{"id":1,"username":"alice","nickname":"Alice"}',
    });
    await SPUtils.init();

    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) => DBUtils.createTables(db),
      ),
    );
    DBUtils.useTestDatabase(db);

    final repo = WishRepository();
    await repo.insertWish(WishModel(
      content: 'cloud public',
      visibility: WishVisibility.public,
      status: WishStatus.unrealized,
      storageMode: StorageMode.cloud,
      serverId: 1,
      createdAt: 1,
      isDeleted: false,
      ownerUsername: 'alice',
    ));
    await repo.insertWish(WishModel(
      content: 'cloud private',
      visibility: WishVisibility.private,
      status: WishStatus.unrealized,
      storageMode: StorageMode.cloud,
      serverId: 2,
      createdAt: 2,
      isDeleted: false,
      ownerUsername: 'alice',
    ));
    await repo.insertWish(WishModel(
      content: 'smart public',
      visibility: WishVisibility.public,
      status: WishStatus.unrealized,
      storageMode: StorageMode.smart,
      serverId: 3,
      createdAt: 3,
      isDeleted: false,
      ownerUsername: 'alice',
    ));

    final auth = AuthModel()..restore();
    expect(auth.isLoggedIn, isTrue);

    await auth.logout();

    final rows = await db.query(WishTable.name);
    expect(auth.isLoggedIn, isFalse);
    expect(rows.map((e) => e[WishTable.colContent]), ['smart public']);
    expect(SPUtils.getString(SPKey.token), isNull);

    await db.close();
  });
}
