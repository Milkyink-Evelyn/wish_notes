import 'package:flutter/foundation.dart';
import '../utils/sp_utils.dart';
import '../utils/auth_api.dart';

class AuthModel extends ChangeNotifier {
  // 实例化 API 请求类
  final AuthApi _api = AuthApi();

  String? _token;
  String? _username;
  String? _nickname;
  bool _isLoading = false;
  String? _errorMsg;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoading => _isLoading;
  String? get errorMsg => _errorMsg;

  /// App 启动时从本地读取 Token，恢复登录状态
  void restore() {
    _token = SPUtils.getString(SPKey.token);
    notifyListeners();// 通知 UI 刷新
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMsg = null;
    notifyListeners(); // 转圈圈~

    try {
      final userData = await _api.login(username, password);

      _token = userData['token'];
      _username = userData['username'];
      _nickname = userData['nickname'] ?? _username;

      if (_token != null) {
        await SPUtils.setString(SPKey.token, _token!);
      }

      _isLoading = false;
      notifyListeners(); //登陆成功
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMsg = e.toString().replaceAll('Exception: ', '');
      notifyListeners(); //登录失败 
      return false;
    }
  }

  Future<bool> register(String username, String password, String nickname) async {
    _isLoading = true;
    _errorMsg = null;
    notifyListeners(); // 转圈圈~

    try {
      final userData = await _api.register(username, password, nickname);

      _token = userData['token'];
      _username = userData['username'];
      _nickname = userData['nickname'] ?? _username;

      if (_token != null) {
        await SPUtils.setString(SPKey.token, _token!);
      }

      _isLoading = false;
      notifyListeners(); //注册成功
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMsg = e.toString().replaceAll('Exception: ', '');
      notifyListeners(); //注册失败 
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    _nickname = null;
    await SPUtils.remove(SPKey.token);
    notifyListeners(); // 退出登录
  }
}