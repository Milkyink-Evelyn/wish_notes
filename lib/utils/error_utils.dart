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

/// 登录 / 注册的错误文案
/// 后端给了中文提示就直接用, 否则按状态码和网络异常类型给常见原因
String authErrorMessage(Object error, {required bool isLogin}) {
  final fallback = isLogin ? '登录失败, 请稍后重试' : '注册失败, 请稍后重试';

  // 接口返回 success=false 时抛的是普通 Exception, message 已经拼在前缀后面
  if (error is! DioException) {
    final text = error.toString().replaceAll('Exception: ', '').trim();
    final prefix = isLogin ? '登录失败: ' : '注册失败: ';
    final message = text.startsWith(prefix)
        ? text.substring(prefix.length).trim()
        : text;
    if (message.isEmpty || message == '未知错误') return fallback;
    return message;
  }

  final backendMessage = _backendMessage(error);
  if (backendMessage != null) return backendMessage;

  final status = error.response?.statusCode;
  if (status != null) {
    if (status == 400) {
      return isLogin ? '用户名或密码错误' : '注册信息有误, 请检查后重试';
    }
    if (status == 401) {
      return isLogin ? '用户名或密码错误' : '登录已失效, 请重新登录';
    }
    if (status == 403) return '没有权限进行该操作';
    if (status == 404) return '接口地址不存在, 请检查网络环境';
    if (status == 409) return isLogin ? '用户名或密码错误' : '用户名已被使用';
    if (status == 422) return '提交的信息不符合要求, 请检查后重试';
    if (status == 429) return '操作太频繁, 请稍后再试';
    if (status >= 500) return '服务器开小差了, 请稍后再试';
  }

  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return '网络连接超时, 请检查网络后重试';
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.unknown) {
    return '网络连接错误, 请检查网络后重试';
  }
  if (error.type == DioExceptionType.badCertificate) {
    return '网络连接不安全, 请检查网络环境';
  }
  if (error.type == DioExceptionType.cancel) return '请求已取消';

  return fallback;
}

/// 只采用带中文的后端提示, 避免把 "Unauthorized" 这类英文原文直接抛给用户
String? _backendMessage(DioException error) {
  final data = error.response?.data;
  if (data is! Map) return null;

  final message = data['message'];
  if (message is! String) return null;

  final text = message.trim();
  if (text.isEmpty) return null;
  return RegExp(r'[\u4e00-\u9fa5]').hasMatch(text) ? text : null;
}
