import 'api_response.dart';
import 'http.dart';

class WishApi {
  /// 获取当前用户的心愿列表(云端)
  Future<List<Map<String, dynamic>>> fetchMyWishes() async {
    try {
      final response = await Http().get('/wishes/me');
      return unwrapList(response, fallbackMessage: '获取我的心愿失败');
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 获取广场的公开心愿(云端, 游客也能访问)
  Future<List<Map<String, dynamic>>> fetchPublicWishes() async {
    try {
      final response = await Http().get('/wishes', skipAuth: true);
      return unwrapList(response, fallbackMessage: '获取公开心愿失败');
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }

  /// 获取单条心愿详情(含评论)
  Future<Map<String, dynamic>> fetchWishDetail(int serverId, {bool skipAuth = false}) async {
    try {
      final response = await Http().get('/wishes/$serverId', skipAuth: skipAuth);
      return unwrapMap(response, fallbackMessage: '获取心愿详情失败');
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
      return unwrapMap(response, fallbackMessage: '发表评论失败');
    } catch (e) {
      rethrow; // 把错误抛给 UI 层处理
    }
  }

  /// 删除评论
  Future<void> deleteComment(int serverId, int commentId) async {
    try {
      final response = await Http().delete('/wishes/$serverId/comments/$commentId');
      unwrapResponse(response, fallbackMessage: '删除评论失败');
    } catch (e) {
      rethrow; // 把错误抛给 UI 层处理
    }
  }

  /// 删除云端心愿
  Future<void> deleteWish(int serverId) async {
    try {
      final response = await Http().delete('/wishes/$serverId');
      unwrapResponse(response, fallbackMessage: '删除失败');
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
      return unwrapMap(response, fallbackMessage: '创建失败');
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
      unwrapResponse(response, fallbackMessage: '状态更新失败');
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
      unwrapResponse(response, fallbackMessage: '修改心愿失败');
    } catch (e) {
      rethrow; // 把错误抛给 Repository 处理
    }
  }
}
