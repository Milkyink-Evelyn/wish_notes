import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/db_utils.dart';
import '../models/wish_model.dart';
import '../utils/http.dart';
import '../utils/sp_utils.dart';

class WishRepository {
  /// 本地
  /// 获取所有心愿(不包含软删除)
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

  /// 获取“心愿广场”的公开心愿
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

  /// 保存心愿（本地新增）
  Future<int> insertWish(WishModel wish) async {
    final db = DBUtils.db;
    
    // 插入数据库，SQLite 自动处理 local_id 自增
    return await db.insert(
      WishTable.name,
      wish.toMap(),
    );
  }

  /// 墓碑软删除
  Future<void> softDeleteWish(int localId) async {
    final db = DBUtils.db;
    
    // 不执行 delete，而是把 is_deleted 置为 1
    await db.update(
      WishTable.name,
      {WishTable.colIsDeleted: 1},
      where: '${WishTable.colLocalId} = ?',
      whereArgs: [localId],
    );
  }
}