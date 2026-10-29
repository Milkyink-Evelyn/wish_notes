import 'http.dart';

class WishApi {
  /// 获取当前用户的心愿列表(云端)
  Future<List<Map<String, dynamic>>> fetchMyWishes() async {
    try {
      final response = await Http().get('/wishes/me');
      final data = response.data;

      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception(data['message'] ?? '获取我的心愿失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 获取广场的公开心愿(云端, 游客也能访问)
  Future<List<Map<String, dynamic>>> fetchPublicWishes() async {
    try {
      final response = await Http().get('/wishes', skipAuth: true);
      final data = response.data;

      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception(data['message'] ?? '获取公开心愿失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 获取单条心愿详情(含评论)
  Future<Map<String, dynamic>> fetchWishDetail(int serverId, {bool skipAuth = false}) async {
    try {
      final response = await Http().get('/wishes/$serverId', skipAuth: skipAuth);
      final data = response.data;

      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      } else {
        throw Exception(data['message'] ?? '获取心愿详情失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 UI 层处理
    }
  }

  /// 发表评论
  Future<Map<String, dynamic>> addComment(int serverId, String content) async {
    try {
      final response = await Http().post('/wishes/$serverId/comments', data: {
        'content': content,
      });
      final data = response.data;

      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      } else {
        throw Exception(data['message'] ?? '发表评论失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 UI 层处理
    }
  }

  /// 删除评论
  Future<void> deleteComment(int serverId, int commentId) async {
    try {
      final response = await Http().delete('/wishes/$serverId/comments/$commentId');
      final data = response.data;

      if (data['success'] != true) {
        throw Exception(data['message'] ?? '删除评论失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 UI 层处理
    }
  }

  /// 删除云端心愿
  Future<void> deleteWish(int serverId) async {
    try {
      final response = await Http().delete('/wishes/$serverId');
      final data = response.data;

      if (data['success'] != true) {
        throw Exception(data['message'] ?? '删除失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 创建云端心愿
  Future<Map<String, dynamic>> createWish(String content, String visibility) async {
    try {
      final response = await Http().post('/wishes', data: {
        'content': content,
        'visibility':visibility,
      });
      final data = response.data;

      if (data['success'] == true) {
        return data['data']; // 返回包含云端分配的 id 的数据
      } else {
        throw Exception(data['message'] ?? '创建失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 更新云端心愿状态
  Future<void> updateWishStatus(int serverId, String status) async {
    try {
      final response = await Http().patch('/wishes/$serverId/status', data: {
        'status': status,
      });
      final data = response.data;
      if (data['success'] != true) {
        throw Exception(data['message'] ?? '状态更新失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 修改云端心愿内容或可见性
  Future<void> updateWish(int serverId, String content, String visibility) async {
    try {
      final response = await Http().put('/wishes/$serverId', data: {
        'content': content,
        'visibility': visibility,
      });
      final data = response.data;
      if (data['success'] != true) {
        throw Exception(data['message'] ?? '修改心愿失败');
      }
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }
}