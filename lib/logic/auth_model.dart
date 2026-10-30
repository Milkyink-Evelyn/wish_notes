import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../repositories/wish_repository.dart';
import '../utils/sp_utils.dart';
import '../utils/auth_api.dart';

class AuthModel extends ChangeNotifier {
  // 实例化 API 请求类
  final AuthApi _api = AuthApi();

  String? _token;
  int? _userId;
  String? _username;
  String? _nickname;
  bool _isLoading = false;
  String? _errorMsg;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  int? get userId => _userId;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoading => _isLoading;
  String? get errorMsg => _errorMsg;

  /// App 启动时从本地读取 Token 和用户信息,恢复登录状态
  void restore() {
    _token = SPUtils.getString(SPKey.token);

    final userInfo = SPUtils.getString(SPKey.userInfo);
    if (userInfo != null && userInfo.isNotEmpty) {
      try {
        final data = jsonDecode(userInfo) as Map<String, dynamic>;
        _userId = data['id'] as int?;
        _username = data['username'] as String?;
        _nickname = data['nickname'] as String?;
      } catch (e) {
        debugPrint('恢复用户信息失败: $e');
      }
    }

    // 旧版本只存了 Token, 没有用户信息, 直接当作未登录
    if (_token != null && _token!.isNotEmpty && _username == null) {
      _token = null;
      SPUtils.remove(SPKey.token);
    }

    notifyListeners();// 通知 UI 刷新
  }

  /// 登录/注册成功后,把用户信息一起存起来
  Future<void> _saveUserInfo() async {
    await SPUtils.setString(SPKey.userInfo, jsonEncode({
      'id': _userId,
      'username': _username,
      'nickname': _nickname,
    }));
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMsg = null;
    notifyListeners(); // 转圈圈~

    try {
      final userData = await _api.login(username, password);

      _token = userData['token'];
      _userId = userData['id'] as int?;
      _username = userData['username'];
      _nickname = userData['nickname'] ?? _username;

      if (_token != null) {
        await SPUtils.setString(SPKey.token, _token!);
        await _saveUserInfo();
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
      _userId = userData['id'] as int?;
      _username = userData['username'];
      _nickname = userData['nickname'] ?? _username;

      if (_token != null) {
        await SPUtils.setString(SPKey.token, _token!);
        await _saveUserInfo();
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
    _userId = null;
    _username = null;
    _nickname = null;
    await SPUtils.remove(SPKey.token);
    await SPUtils.remove(SPKey.userInfo);

    // 云端专属的心愿留在本机会被当成游客数据展示, 退出时直接清掉
    try {
      await WishRepository().clearCloudWishes();
    } catch (e) {
      debugPrint('清理云端心愿失败: $e');
    }

    notifyListeners(); // 退出登录
  }
}