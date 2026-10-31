import 'package:flutter/foundation.dart';

/// 全局登录失效事件
/// 网络层发现 Token 失效后通知界面, 避免同步失败只在控制台打印
class AuthEvents {
  AuthEvents._();

  /// 数值每加一次代表一次登录失效
  static final ValueNotifier<int> sessionExpired = ValueNotifier<int>(0);

  // 同时有好几个请求拿到 401 时, 只提醒一次
  static bool _notified = false;

  static void notifySessionExpired() {
    if (_notified) return;
    _notified = true;
    sessionExpired.value++;
  }

  /// 重新登录成功后, 允许下次再提醒
  static void reset() {
    _notified = false;
  }
}
