import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'auth_events.dart';
import 'sp_utils.dart';

/// Dio封装
class Http {
  static const String baseUrl = 'https://mobile.sduonline.cn/api';

  late final Dio _dio;
  static Http? _instance;

  /// 工厂构造函数,返回单例实例
  factory Http() => _getInstance();

  static Http _getInstance() {
    if (_instance == null) {
      _instance = Http._internal();
      _instance!._dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      // 添加拦截器
      _instance!._dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          // 在每次请求前,自动从本地取出 Token 塞进 Header
          // 公开接口可以跳过 Token, 避免本地残留的失效 Token 把匿名请求也挡掉
          final token = options.extra['skipAuth'] == true
              ? null
              : SPUtils.getString(SPKey.token);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
            // 记下来, 方便判断 401 是登录失效还是匿名请求被打回
            options.extra['hadAuth'] = true;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // 暂时不做任何处理,直接返回响应
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          // 带着 Token 还被拒才是登录失效, 登录接口密码错误不算
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['hadAuth'] == true) {
            debugPrint('登录已过期,请重新登录');
            AuthEvents.notifySessionExpired();
          }
          return handler.next(e); //抛出,UI层弹提示
        },
      ));

      // 调试日志只在 debug 包打印, release 不输出也不泄露接口数据
      if (kDebugMode) {
        _instance!._dio.interceptors.add(_AppLogInterceptor());
      }
    }
    return _instance!;
  }

  /// 私有构造函数,防止外部实例化
  Http._internal();

  /// 封装GET请求
  Future<Response<T>> get<T>(String path, {
    Map<String, dynamic>? queryParameters,
    bool skipAuth = false,
    bool skipLog = false,
  }) async {
    return await _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: Options(extra: {'skipAuth': skipAuth, 'skipLog': skipLog}),
    );
  }

  /// 封装POST请求
  Future<Response<T>> post<T>(String path, {dynamic data, bool skipAuth = false}) async {
    return await _dio.post<T>(
      path,
      data: data,
      options: Options(extra: {'skipAuth': skipAuth}),
    );
  }

  /// 封装DELETE请求
  Future<Response<T>> delete<T>(String path) async {
    return await _dio.delete<T>(path);
  }

  /// 封装PATCH请求
  Future<Response<T>> patch<T>(String path, {dynamic data}) async {
    return await _dio.patch<T>(path, data: data);
  }

  /// 封装PUT请求
  Future<Response<T>> put<T>(String path, {dynamic data}) async {
    return await _dio.put<T>(path, data: data);
  }
}

/// 接口日志: 支持单条请求跳过, 内容太长时截断, 避免刷屏
class _AppLogInterceptor extends LogInterceptor {
  static const int _maxLength = 2000;

  _AppLogInterceptor()
      : super(
          request: true,
          requestHeader: true,
          requestBody: true,
          responseHeader: true,
          responseBody: true,
          error: true,
          logPrint: _printLog,
        );

  static void _printLog(Object object) {
    final text = object.toString();
    if (text.length <= _maxLength) {
      debugPrint(text);
      return;
    }
    debugPrint('${text.substring(0, _maxLength)}...(共 ${text.length} 字符, 已截断)');
  }

  static bool _skip(RequestOptions options) =>
      options.extra['skipLog'] == true;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_skip(options)) {
      handler.next(options);
      return;
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_skip(response.requestOptions)) {
      handler.next(response);
      return;
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_skip(err.requestOptions)) {
      handler.next(err);
      return;
    }
    super.onError(err, handler);
  }
}