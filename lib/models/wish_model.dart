import 'dart:convert';

/// 存储模式
enum StorageMode {
  /// 本地存储
  local,
  /// 云端存储
  cloud,
  /// 智能存储 (本地+云端, 本地优先)
  smart;

  /// 转成与数据库表一致的大写字符串
  String get value => name.toUpperCase();

  /// 从数据库字符串转回枚举
  static StorageMode fromString(String str) {
    return StorageMode.values.firstWhere(
      (e) => e.value == str, 
      orElse: () => StorageMode.cloud, // 兜底，防止数据库脏数据
    );
  }
}

/// 可见性
enum WishVisibility {
  /// 公开
  public,
  /// 私密
  private;

  /// 转成与数据库表一致的大写字符串
  String get value => name.toUpperCase();

  /// 从数据库字符串转回枚举
  static WishVisibility fromString(String str) {
    return WishVisibility.values.firstWhere(
      (e) => e.value == str, 
      orElse: () => WishVisibility.private, // 兜底，防止数据库脏数据
    );
  }
}

class WishModel {
  final int? localId;
  final int? serverId;
  final String content;
  final WishVisibility visibility;
  final String status;
  final StorageMode storageMode;
  final int createdAt;
  final bool isDeleted;
  final String? category;
  final List<CommentModel> comments;

  WishModel({
    this.localId,
    this.serverId,
    required this.content,
    required this.visibility,
    required this.status,
    required this.storageMode,
    required this.createdAt,
    required this.isDeleted,
    this.category,
    this.comments = const [],
  });

  /// 将对象转成Map，以便存入数据库
  Map<String, dynamic> toMap() {
    return {
      'local_id': localId,
      'server_id': serverId,
      'content': content,
      'visibility': visibility.value,
      'status': status,
      'storage_mode': storageMode.value,
      'created_at': createdAt,
      'is_deleted': isDeleted ? 1 : 0,
      'category': category,
      'comments_json': jsonEncode(comments.map((e) => e.toJson()).toList()),
    };
  }

  /// 从Map创建对象，以便从数据库读取
  factory WishModel.fromMap(Map<String, dynamic> map) {

    final commentsStr = map['comments_json'] as String?;
    final List<CommentModel> commentList = commentsStr != null && commentsStr.isNotEmpty
        ? (jsonDecode(commentsStr) as List).map((e) => CommentModel.fromJson(e)).toList()
        : [];

    return WishModel(
      localId: map['local_id'] as int?,
      serverId: map['server_id'] as int?,
      content: map['content'] as String,
      visibility: WishVisibility.fromString(map['visibility'] as String),
      status: map['status'] as String,
      storageMode: StorageMode.fromString(map['storage_mode'] as String),
      createdAt: map['created_at'] as int,
      isDeleted: (map['is_deleted'] as int) == 1,
      category: map['category'] as String?,
      comments: commentList,
    );
  }

  /// 解析云端接口返回的JSON数据
  factory WishModel.fromJson(Map<String, dynamic> json, StorageMode mode) {
    return WishModel(
      localId: null, // 云端拉下暂未存到本地, ID为null
      serverId: json['id'] as int?, // 云端ID
      content: json['content'] as String,
      visibility: WishVisibility.fromString(json['visibility'] ?? 'PRIVATE'),
      status: json['status'] ?? 'UNREALIZED',
      storageMode: mode,
      // 云端返回的时间戳是字符串格式, 需要解析成DateTime再转成毫秒数
      createdAt: DateTime.parse(json['created_at'] as String).millisecondsSinceEpoch,
      isDeleted: false, // 云端数据默认未删除
      category: null, // 后端接口没有分类字段, 只能沃自己来了(沃悲伤.jpg)
      comments: (json['comments'] as List? ?? []).map((e) => CommentModel.fromJson(e)).toList(),
    );
  }
}

class CommentModel {
  final int id;
  final String content;
  final String username;
  final String nickname;
  final String createdAt; // 接口返回的是字符串日期

  CommentModel({
    required this.id,
    required this.content,
    required this.username,
    required this.nickname,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as int,
      content: json['content'] as String,
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'username': username,
      'nickname': nickname,
      'createdAt': createdAt,
    };
  }
}