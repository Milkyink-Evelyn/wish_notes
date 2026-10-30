import 'package:dio/dio.dart';

/// 统一解析后端的 { success, data, message } 响应
/// success 不是 true 就抛异常, 错误信息优先用后端返回的 message
/// [prefix] 给错误文案加前缀, 比如登录接口的"登录失败: "
dynamic unwrapResponse(
  Response response, {
  required String fallbackMessage,
  String prefix = '',
}) {
  final body = response.data;
  if (body is Map && body['success'] == true) {
    return body['data'];
  }

  final message = body is Map ? body['message'] : null;
  throw Exception('$prefix${message ?? fallbackMessage}');
}

/// 需要返回对象的接口用这个, 比如登录、注册、心愿详情
Map<String, dynamic> unwrapMap(
  Response response, {
  required String fallbackMessage,
  String prefix = '',
}) {
  final data = unwrapResponse(response, fallbackMessage: fallbackMessage, prefix: prefix);
  if (data is Map) return Map<String, dynamic>.from(data);

  throw Exception('$prefix$fallbackMessage');
}

/// 需要返回列表的接口用这个, 比如我的心愿、心愿广场
List<Map<String, dynamic>> unwrapList(
  Response response, {
  required String fallbackMessage,
}) {
  final data = unwrapResponse(response, fallbackMessage: fallbackMessage);
  if (data is List) return List<Map<String, dynamic>>.from(data);

  throw Exception(fallbackMessage);
}
