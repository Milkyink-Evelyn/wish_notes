/// 补两位, 统一时间格式
String _two(int value) => value.toString().padLeft(2, '0');

/// 把心愿创建时间格式化成列表里显示的短文本
/// 今天的显示"今天 HH:mm", 其他日期显示"yyyy-MM-dd"
String formatWishTime(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// 详情页用的详细时间, 精确到分
String formatDetailTime(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
}

/// 评论时间是接口返回的字符串, 可能是时间戳, 也可能是 ISO 时间
/// 解析失败就原样返回, 免得把脏数据显示成 1970 年
String formatCommentTime(String raw) {
  final asInt = int.tryParse(raw);
  final dt = asInt != null
      ? DateTime.fromMillisecondsSinceEpoch(asInt)
      : DateTime.tryParse(raw);

  if (dt == null) return raw;

  // 评论时间也是详情页, 统一显示到分
  return formatDetailTime(dt.toLocal().millisecondsSinceEpoch);
}
