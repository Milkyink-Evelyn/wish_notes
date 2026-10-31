import 'package:shared_preferences/shared_preferences.dart';

///用枚举同一管理Key,防止手误
enum SPKey {
  token('auth_token'),
  userInfo('user_info'),
  rememberedUsername('remembered_username'),
  cloudImportMode('cloud_import_mode'),
  cloudKeepIds('cloud_keep_ids');

  final String key;
  const SPKey(this.key);

  static Set<String> get allowList => SPKey.values.map((e) => e.key).toSet();
}

/// SP工具类
class SPUtils {
  /// 私有构造函数,防止外部实例化
  SPUtils._();

  static late final SharedPreferencesWithCache _prefs;

  /// 在应用启动时初始化SharedPreferences
  static Future<void> init() async {
    _prefs = await SharedPreferencesWithCache.create(
      cacheOptions:SharedPreferencesWithCacheOptions(
        allowList: SPKey.allowList, // 白名单, 只允许读写这些Keys
      ),
    );
  }

  /// 封装SharedPreferences的get方法
  static String? getString(SPKey key) => _prefs.getString(key.key);

  /// 封装SharedPreferences的set方法
  static Future<void> setString(SPKey key, String value) => _prefs.setString(key.key, value);

  /// 封装SharedPreferences的remove方法
  static Future<void> remove(SPKey key) => _prefs.remove(key.key);
  
}