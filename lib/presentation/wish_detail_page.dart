import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/dialog_utils.dart';
import '../utils/time_utils.dart';
import '../utils/toast_utils.dart';
import '../utils/wish_api.dart';
import '../widgets/app_card.dart';
import '../widgets/comment_tile.dart';
import '../widgets/wish_tags.dart';
import 'login_page.dart';
import 'wish_form_page.dart';

class WishDetailPage extends StatefulWidget {
  final WishModel wish;
  const WishDetailPage({super.key, required this.wish});

  @override
  State<WishDetailPage> createState() => _WishDetailPageState();
}

class _WishDetailPageState extends State<WishDetailPage> {
  final WishRepository _repo = WishRepository();
  final WishApi _api = WishApi();
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();

  late WishModel _wish;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _wish = widget.wish;
    _refreshDetail();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  /// 静默拉一次云端详情, 顺便刷新评论
  Future<void> _refreshDetail() async {
    final serverId = _wish.serverId;
    if (serverId == null) return;

    try {
      // 游客看公开详情不需要 Token, 避免旧 Token 失效时连详情都打不开
      final isLoggedIn = context.read<AuthModel>().isLoggedIn;
      final json = await _api.fetchWishDetail(serverId, skipAuth: !isLoggedIn);
      final cloudWish = WishModel.fromJson(json, _wish.storageMode);
      if (!mounted) return;

      // 广场缓存整体跟随云端; 自己的数据保持本地优先, 免得冲掉还没同步的修改
      final isCache = _wish.isPublicCache;
      final updated = _wish.copyWith(
        content: isCache ? cloudWish.content : null,
        visibility: isCache ? cloudWish.visibility : null,
        status: isCache ? cloudWish.status : null,
        createdAt: isCache ? cloudWish.createdAt : null,
        comments: cloudWish.comments,
        ownerUsername: isCache ? cloudWish.ownerUsername : null,
      );

      if (isCache) {
        await _repo.updateWishLocal(updated);
      } else {
        await _repo.updateWishComments(updated);
      }
      if (!mounted) return;
      setState(() => _wish = updated);
    } catch (e) {
      debugPrint('拉取心愿详情失败: $e');
    }
  }

  /// 先改本地状态, 云端能推就推, 推失败等下次同步
  Future<void> _toggleStatus() async {
    final nextStatus = WishStatus.toggle(_wish.status);
    final updated = _wish.copyWith(status: nextStatus, statusDirty: true);

    await _repo.updateWishStatus(updated);
    if (!mounted) return;

    setState(() => _wish = updated);
    context.showSnack(WishStatus.isRealized(nextStatus) ? '心愿实现啦~' : '已标记为未实现');
    await _pushWishToCloud();
  }

  /// 编辑页保存后会返回新的心愿对象, 直接替换当前展示的数据
  Future<void> _editWish() async {
    final result = await Navigator.push<WishModel>(
      context,
      MaterialPageRoute(builder: (_) => WishFormPage(initialWish: _wish)),
    );

    if (result != null && mounted) {
      setState(() => _wish = result);
      await _pushWishToCloud();
    }
  }

  /// 改完顺手推一次云端, 失败就留给下次下拉同步
  Future<void> _pushWishToCloud() async {
    final serverId = _wish.serverId;
    if (serverId == null || _wish.storageMode == StorageMode.local) return;
    if (!context.read<AuthModel>().isLoggedIn) return;

    try {
      if (_wish.contentDirty) {
        await _repo.pushWishContent(_wish);
        if (mounted) setState(() => _wish = _wish.copyWith(contentDirty: false));
      }
      if (_wish.statusDirty) {
        await _repo.pushWishStatus(_wish);
        if (mounted) setState(() => _wish = _wish.copyWith(statusDirty: false));
      }
    } catch (e) {
      debugPrint('推送心愿修改失败: $e');
    }
  }

  Future<void> _deleteWish() async {
    final confirm = await showConfirmDialog(
      context,
      title: '删除心愿',
      content: '确定要删除这个心愿吗？',
      confirmText: '删除',
    );

    if (confirm != true || !mounted) return;

    // 没上过云的直接删, 上过云的打墓碑, 云端删除交给同步流程
    final localId = _wish.localId;
    if (localId == null) return;

    await _repo.deleteWish(localId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// 评论先发云端, 成功后再把新评论写回本地缓存
  Future<void> _sendComment() async {
    if (_isSending) return;

    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final auth = context.read<AuthModel>();
    final serverId = _wish.serverId;

    if (!auth.isLoggedIn) {
      context.showSnack('登录后才能评论哦~');
      return;
    }
    if (serverId == null) {
      context.showSnack('本地心愿同步到云端后才能评论');
      return;
    }

    setState(() => _isSending = true);

    try {
      final data = await _api.addComment(serverId, content);
      final newComment = CommentModel.fromJson(data);
      final updated = _wish.copyWith(comments: [..._wish.comments, newComment]);
      await _repo.updateWishComments(updated);

      if (!mounted) return;
      setState(() {
        _wish = updated;
        _commentController.clear();
      });
      FocusScope.of(context).unfocus();
      context.showSnack('评论成功~');
    } catch (e) {
      if (mounted) {
        context.showSnack('评论失败: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// 点击“回复”时, 把回复对象塞进输入框
  void _startReply(CommentModel comment) {
    if (!context.read<AuthModel>().isLoggedIn) {
      context.showSnack('登录后才能回复哦~');
      return;
    }

    final nickname = comment.nickname.isNotEmpty
        ? comment.nickname
        : (comment.username.isNotEmpty ? comment.username : '用户');
    final prefix = '回复 @$nickname : ';

    _commentController.value = TextEditingValue(
      text: prefix,
      selection: TextSelection.collapsed(offset: prefix.length),
    );
    _commentFocusNode.requestFocus();
  }

  /// 删除成功后同步移除本地缓存里的这条评论
  Future<void> _deleteComment(CommentModel comment) async {
    final confirm = await showConfirmDialog(
      context,
      title: '删除评论',
      content: '确定要删除这条评论吗？',
      confirmText: '删除',
    );

    if (confirm != true || !mounted) return;

    final serverId = _wish.serverId;
    if (serverId == null) return;

    try {
      await _api.deleteComment(serverId, comment.id);
      final updated = _wish.copyWith(
        comments: _wish.comments.where((e) => e.id != comment.id).toList(),
      );
      await _repo.updateWishComments(updated);

      if (!mounted) return;
      setState(() => _wish = updated);
      context.showSnack('评论已删除');
    } catch (e) {
      if (mounted) {
        context.showSnack('删除评论失败: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  Future<void> _goLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthModel>();
    // 智能存储的私有心愿退出登录后还留在本地, 没登录也要能改
    final offlineEditable = !auth.isLoggedIn &&
        _wish.storageMode == StorageMode.smart &&
        _wish.visibility == WishVisibility.private;
    final isOwner = _wish.ownerUsername == auth.username || offlineEditable;
    final isRealized = WishStatus.isRealized(_wish.status);

    return Scaffold(
      backgroundColor: const Color.fromARGB(189, 255, 255, 255),
      appBar: AppBar(title: const Text('心愿详情')),
      resizeToAvoidBottomInset: true,
      // 心愿卡片和评论一起滚动, 评论输入框固定在底部
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _buildWishCard(isOwner, isRealized),
                const SizedBox(height: 20),
                _buildCommentHeader(),
                const SizedBox(height: 10),
                if (_wish.comments.isEmpty)
                  _buildEmptyComments()
                else
                  ..._wish.comments.map((comment) => _buildCommentTile(comment, auth)),
              ],
            ),
          ),
          _buildCommentInput(auth),
        ],
      ),
    );
  }

  Widget _buildWishCard(bool isOwner, bool isRealized) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部: 状态、可见性和创建时间
          Row(
            children: [
              WishStatusTag(status: _wish.status),
              const SizedBox(width: 8),
              WishVisibilityTag(visibility: _wish.visibility),
              const Spacer(),
              Text(
                formatWishTime(_wish.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _wish.content,
            style: const TextStyle(fontSize: 17, height: 1.6, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              WishCategoryTag(category: _wish.category),
              const SizedBox(width: 10),
              const Icon(Icons.person_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                _wish.ownerUsername ??
                    (_wish.visibility == WishVisibility.public &&
                            _wish.storageMode != StorageMode.local
                        ? '匿名用户'
                        : '本地游客'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          // 只有作者本人能看到操作区
          if (isOwner) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _toggleStatus,
                  icon: Icon(
                    isRealized ? Icons.undo : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(isRealized ? '标记未实现' : '标记已实现'),
                ),
                TextButton.icon(
                  onPressed: _editWish,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: _deleteWish,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentHeader() {
    return Row(
      children: [
        const Text(
          '评论',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 6),
        Text(
          '${_wish.comments.length}',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildEmptyComments() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: const Text(
        '还没有评论, 来抢个沙发吧~',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildCommentTile(CommentModel comment, AuthModel auth) {
    // 自己的评论和作者的评论用不同底色, 方便区分
    final isMine = auth.isLoggedIn &&
        (comment.username == auth.username ||
            (comment.userId != null && comment.userId == auth.userId));
    final isAuthor = _wish.ownerUsername != null && comment.username == _wish.ownerUsername;

    return CommentTile(
      comment: comment,
      isMine: isMine,
      isAuthor: isAuthor,
      onReply: () => _startReply(comment),
      onDelete: () => _deleteComment(comment),
    );
  }

  Widget _buildCommentInput(AuthModel auth) {
    final serverId = _wish.serverId;

    // 未登录时只显示登录引导
    if (!auth.isLoggedIn) {
      return SafeArea(
        top: false,
        child: Container(
          color: Colors.white.withValues(alpha: 0.92),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: GestureDetector(
            onTap: _goLogin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('登录后就可以评论啦~', style: TextStyle(color: Colors.grey)),
                  Spacer(),
                  Text('去登录', style: TextStyle(color: Colors.pinkAccent)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 纯本地心愿还没有 serverId, 评论接口用不了
    if (serverId == null) {
      return SafeArea(
        top: false,
        child: Container(
          color: Colors.white.withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: const Text(
            '本地心愿同步到云端后才能评论',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocusNode,
                minLines: 1,
                maxLines: 3,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(),
                decoration: InputDecoration(
                  hintText: '说点什么吧...',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSending ? null : _sendComment,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _isSending ? Colors.grey.shade300 : Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
