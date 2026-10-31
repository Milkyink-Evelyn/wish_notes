import '../models/wish_model.dart';
import 'sp_utils.dart';

/// 云端新心愿的默认存储方式
/// 没设置时返回 null, 表示每次导入都询问用户
class CloudImportPref {
  CloudImportPref._();

  static StorageMode? read() {
    final raw = SPUtils.getString(SPKey.cloudImportMode);
    if (raw == StorageMode.cloud.value) return StorageMode.cloud;
    if (raw == StorageMode.smart.value) return StorageMode.smart;
    return null;
  }

  static Future<void> save(StorageMode mode) {
    return SPUtils.setString(SPKey.cloudImportMode, mode.value);
  }

  static Future<void> reset() => SPUtils.remove(SPKey.cloudImportMode);
}
