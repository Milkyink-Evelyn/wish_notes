import 'package:dio/dio.dart';

/// 把异常转成能给用户看的文案
/// 后端返回了 message 就用后端的, 否则按异常类型给个兜底
String errorMessage(Object error, {String fallback = '网络异常, 请稍后重试'}) {
  if (error is DioException) {
    if (error.response?.statusCode == 401) {
      return '登录已失效, 请重新登录';
    }

    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      final message = (data['message'] as String).trim();
      if (message.isNotEmpty) return message;
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '网络连接超时, 请稍后重试';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '网络连接失败, 请检查网络后重试';
    }
    return fallback;
  }

  return error.toString().replaceAll('Exception: ', '');
}

/// 401 由登录失效弹窗统一处理, 其他提示就不重复弹了
bool isAuthError(Object error) {
  return error is DioException && error.response?.statusCode == 401;
}
