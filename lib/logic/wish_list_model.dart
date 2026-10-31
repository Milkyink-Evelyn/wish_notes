import 'package:flutter/foundation.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/error_utils.dart';
import '../utils/sp_utils.dart';

/// 一次云端同步的结果
class SyncRefreshResult {
  final List<WishModel> newWishes;
  // 请求失败时不能拿本地现状去清理确认记录, 否则会误删
  final bool success;
  // 失败原因, 界面拿去提示用户
  final String? error;
  // 登录失效会走全局弹窗, 界面上就不再叠加别的提示
  final bool unauthorized;

  const SyncRefreshResult({
    required this.newWishes,
    required this.success,
    this.error,
    this.unauthorized = false,
  });
}

class WishListModel extends ChangeNotifier {
  final WishRepository _repo = WishRepository();

  List<WishModel> _wishes = [];
  bool _isLoading = false;
  WishCategory? _selectedCategory;
  String? _selectedOwner;
  // 状态筛选: null=全部, REALIZED=已实现, UNREALIZED=未实现
  String? _selectedStatus;

  List<WishModel> get wishes => _wishes;
  bool get isLoading => _isLoading;
  WishCategory? get selectedCategory => _selectedCategory;
  String? get selectedOwner => _selectedOwner;
  String? get selectedStatus => _selectedStatus;


  List<String> get uniqueOwners {
    final Set<String> owners = {};
    for (var w in _wishes) {
      if (w.ownerUsername == null) {
        owners.add('__GUEST__');
      } else {
        owners.add(w.ownerUsername!);
      }
    }
    return owners.toList();
  }

  void setCategory(WishCategory? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setOwner(String? owner) {
    _selectedOwner = owner;
    notifyListeners();
  }

  void setStatus(String? status) {
    _selectedStatus = status;
    notifyListeners();
  }

  List<WishModel> get displayWishes {
    return _wishes.where((w) {
      // 1. 分类过滤
      final matchCategory = _selectedCategory == null || w.category == _selectedCategory;
      
      // 2. 归属者过滤
      bool matchOwner = true;
      if (_selectedOwner == '__GUEST__') {
        matchOwner = w.ownerUsername == null;
      } else if (_selectedOwner != null) {
        matchOwner = w.ownerUsername == _selectedOwner;
      }

      // 3. 状态过滤
      final matchStatus = _selectedStatus == null || w.status == _selectedStatus;

      return matchCategory && matchOwner && matchStatus;
    }).toList();
  }
  
  /// 从本地加载数据(不请求网络)
  Future<void> loadLocalData(String? username) async {
    _isLoading = true;
    notifyListeners();

    try {
      _wishes = await _repo.getMyWishes(ownerUsername: username);
    } catch (e) {
      debugPrint('加载本地数据失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 下拉刷新: 触发云端同步,然后再加载本地数据
  /// 返回这次从云端新拉到本地的心愿, 页面用它询问存储方式
  Future<SyncRefreshResult> syncAndRefresh(String? username) async {
    final token = SPUtils.getString(SPKey.token);
    var newWishes = <WishModel>[];
    var success = true;
    String? error;
    var unauthorized = false;
    try {
      if (token != null && token.isNotEmpty) {
        // 已登录：执行完整的云端同步流程
        newWishes = await _repo.syncAll(username);
      } else {
        // 未登录：只重新加载本地数据,不请求网络
        debugPrint('未登录,仅刷新本地');
      }
    } catch (e) {
      debugPrint('同步刷新失败: $e');
      success = false;
      unauthorized = isAuthError(e);
      error = errorMessage(e, fallback: '同步失败, 请稍后重试');
    } finally {
      _wishes = await _repo.getMyWishes(ownerUsername: username);
      notifyListeners();
    }
    return SyncRefreshResult(
      newWishes: newWishes,
      success: success,
      error: error,
      unauthorized: unauthorized,
    );
  }
}