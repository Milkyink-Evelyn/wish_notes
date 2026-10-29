import 'package:flutter/foundation.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/sp_utils.dart';

class WishListModel extends ChangeNotifier {
  final WishRepository _repo = WishRepository();

  List<WishModel> _wishes = [];
  bool _isLoading = false;
  WishCategory? _selectedCategory;
  String? _selectedOwner;

  List<WishModel> get wishes => _wishes;
  bool get isLoading => _isLoading;
  WishCategory? get selectedCategory => _selectedCategory;
  String? get selectedOwner => _selectedOwner;


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

      return matchCategory && matchOwner;
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
  Future<void> syncAndRefresh(String? username) async {
    final token = SPUtils.getString(SPKey.token);
    try {
      if (token != null && token.isNotEmpty) {
        // 已登录：执行完整的云端同步流程
        await _repo.syncAll(username);
      } else {
        // 未登录：只重新加载本地数据,不请求网络
        debugPrint('未登录,仅刷新本地');
      }
    } catch (e) {
      debugPrint('同步刷新失败: $e');
    } finally {
      _wishes = await _repo.getMyWishes(ownerUsername: username);
      notifyListeners();
    }
  }
}