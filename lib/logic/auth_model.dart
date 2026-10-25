import 'package:flutter/foundation.dart';
import '../utils/sp_utils.dart';
import '../utils/auth_api.dart';

/// AuthModel类用于管理用户身份验证状态
class AuthModel extends ChangeNotifier {
  final AuthApi _api = AuthApi();

  // 内部状态变量
  String? _token;
  String? _username;
  String? _nickname;
  bool _isLoading = false;
  String? _errorMsg;

  // 公共getter方法
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoading => _isLoading;
  String? get errorMsg => _errorMsg;

  /// 启动App时恢复用户登录状态
  void restoreLoginState() {
    _token = SPUtils.getString(SPKey.token);
    notifyListeners();
  }

  /// 登录方法
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMsg = null;
    notifyListeners(); // 通知UI层状态已更新，显示加载中状态
    try {
      final userData = await _api.login(username, password);
      _token = userData['token'];
      _username = userData['username'];
      _nickname = userData['nickname'] ?? _username;

      // Token持久化存储到SharedPreferences
      if (_token != null) {
        await SPUtils.setString(SPKey.token, _token!);
      }
      _isLoading = false;
      notifyListeners(); // 通知UI层状态已更新，登录成功
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMsg = e.toString().replaceAll('Exception: ', '');
      notifyListeners(); // 通知UI层状态已更新，登录失败
      return false;
    }
  }

  /// 退出登录方法
  Future<void> logout() async {
    _token = null;
    _username = null;
    _nickname = null;
    await SPUtils.remove(SPKey.token);
    notifyListeners(); // 通知UI层状态已更新，用户已退出登录
  }
}