import 'package:flutter/foundation.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/sp_utils.dart';

class WishListModel extends ChangeNotifier {
  final WishRepository _repo = WishRepository();

  List<WishModel> _wishes = [];
  bool _isLoading = false;

  List<WishModel> get wishes => _wishes;
  bool get isLoading => _isLoading;

  /// 从本地加载数据(不请求网络)
  Future<void> loadLocalData() async {
    _isLoading = true;
    notifyListeners(); // 转圈圈~

    try {
      _wishes = await _repo.getMyWishes();
    } catch (e) {
      debugPrint('加载本地数据失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners(); // 加载结束
    }
  }

  /// 下拉刷新: 触发云端同步，然后再加载本地数据
  Future<void> syncAndRefresh() async {
    try {
      final token = SPUtils.getString(SPKey.token);
      if (token == null || token.isEmpty) {
        // 未登录：只重新加载本地数据，不请求网络
        _wishes = await _repo.getMyWishes();
        notifyListeners();// 更新结束
        debugPrint('未登录，仅刷新本地数据');
        return;
      }

      // 已登录：执行完整的云端同步流程
      await _repo.syncAll();
      _wishes = await _repo.getMyWishes();
    } catch (e) {
      debugPrint('同步刷新失败: $e');
    } finally {
      notifyListeners(); // 更新结束
    }
  }
}