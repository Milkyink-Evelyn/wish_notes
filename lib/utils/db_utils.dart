import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// 心愿表结构常量
abstract class WishTable {
  /// 表名
  static const String name = 'wishes';
  /// 本地主键
  static const String colLocalId = 'local_id';
  /// 云端主键, 若本地存储则为NULL
  static const String colServerId = 'server_id';
  /// 心愿内容
  static const String colContent = 'content';
  /// 可见性: PUBLIC / PRIVATE
  static const String colVisibility = 'visibility';
  /// 状态: UNREALIZED / REALIZED
  static const String colStatus = 'status';
  /// 存储模式: CLOUD / LOCAL / SMART
  static const String colStorageMode = 'storage_mode';
  /// 创建时间戳
  static const String colCreatedAt = 'created_at';
  /// 墓碑机制: 0正常, 1已软删除
  static const String colIsDeleted = 'is_deleted';
  /// 本地分类
  static const String colCategory = 'category';
  /// 评论
  static const String colComments = 'comments_json';
  /// 评论作者用户名
  static const String colOwnerUsername = 'owner_username';
}

/// DB工具类
class DBUtils {
  DBUtils._();
  static late final Database _db;

  /// 在应用启动时初始化数据库
  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wish_note.db');

    _db = await openDatabase(
      path,
      version: 2,
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
            ${WishTable.colOwnerUsername} TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ${WishTable.name} ADD COLUMN ${WishTable.colOwnerUsername} TEXT'
          );
        }
      },
    );
  }

  static Database get db => _db;
}