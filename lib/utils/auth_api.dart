import 'api_response.dart';
import 'http.dart';

/// AuthApi类用于处理与身份验证相关的API请求
class AuthApi {
  /// 登录接口 
  /// 
  /// 参数: [username] 用户名, [password] 密码
  /// 
  /// 返回: Map{ [token] 令牌, [type] Token类型(固定为"Bearer"), [id] 用户ID, [username] 用户名, [nickname] 昵称 }
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await Http().post('/auth/login', data: {
        'username': username,
        'password': password,
      });

      return unwrapMap(response, fallbackMessage: '未知错误', prefix: '登录失败: ');
    } catch (e) {
      rethrow; // 将异常抛出给UI层处理
    }
  }
  /// 注册接口
  ///
  /// 参数: [username] 用户名, [password] 密码, [nickname] 昵称
  /// 
  /// 返回: Map{ [token] 令牌, [type] Token类型(固定为"Bearer"), [id] 用户ID, [username] 用户名, [nickname] 昵称 }
  Future<Map<String, dynamic>> register(String username, String password, String nickname) async {
    try {
      final response = await Http().post('/auth/register', data: {
        'username': username,
        'password': password,
        if (nickname.isNotEmpty) 'nickname': nickname,
      });

      return unwrapMap(response, fallbackMessage: '未知错误', prefix: '注册失败: ');
    } catch (e) {
      rethrow; // 将异常抛出给UI层处理
    }
  }
}

