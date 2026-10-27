import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'sp_utils.dart';

/// Dio封装
class Http {
  static const String baseUrl = 'https://mobile.sduonline.cn/api';

  late final Dio _dio;
  static Http? _instance;

  /// 工厂构造函数，返回单例实例
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
          // 在每次请求前，自动从本地取出 Token 塞进 Heade
          final token = SPUtils.getString(SPKey.token);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // 暂时不做任何处理，直接返回响应
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          if (e.response?.statusCode == 401) {
            debugPrint('登录已过期,请重新登录');
          }
          return handler.next(e); //抛出,UI层弹提示
        },
      ));

      // 调试日志(开发用),能在控制台看到请求参数和返回值
      _instance!._dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: (object) {
          debugPrint(object as String?);
        },
      ));
    }
    return _instance!;
  }

  /// 私有构造函数，防止外部实例化
  Http._internal();

  /// 封装GET请求
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    return await _dio.get<T>(path, queryParameters: queryParameters);
  }

  /// 封装POST请求
  Future<Response<T>> post<T>(String path, {dynamic data}) async {
    return await _dio.post<T>(path, data: data);
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