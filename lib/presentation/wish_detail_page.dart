import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../logic/auth_model.dart';
import '../models/wish_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/toast_utils.dart';
import '../utils/wish_api.dart';
import 'login_page_test.dart';
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

      await _repo.updateWishLocal(updated);
      if (!mounted) return;
      setState(() => _wish = updated);
    } catch (e) {
      debugPrint('拉取心愿详情失败: $e');
    }
  }

  Future<void> _toggleStatus() async {
    final nextStatus = _wish.status == 'REALIZED' ? 'UNREALIZED' : 'REALIZED';
    final updated = _wish.copyWith(status: nextStatus);

    await _repo.updateWishLocal(updated);
    if (!mounted) return;

    setState(() => _wish = updated);
    context.showSnack(nextStatus == 'REALIZED' ? '心愿实现啦~' : '已标记为未实现');
    await _pushWishToCloud();
  }

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
      await _api.updateWish(serverId, _wish.content, _wish.visibility.value);
      await _api.updateWishStatus(serverId, _wish.status);
    } catch (e) {
      debugPrint('推送心愿修改失败: $e');
    }
  }

  Future<void> _deleteWish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除心愿'),
        content: const Text('确定要删除这个心愿吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final localId = _wish.localId;
    if (localId == null) return;

    await _repo.softDeleteWish(localId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

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
      await _repo.updateWishLocal(updated);

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

  Future<void> _deleteComment(CommentModel comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定要删除这条评论吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final serverId = _wish.serverId;
    if (serverId == null) return;

    try {
      await _api.deleteComment(serverId, comment.id);
      final updated = _wish.copyWith(
        comments: _wish.comments.where((e) => e.id != comment.id).toList(),
      );
      await _repo.updateWishLocal(updated);

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
    final isOwner = _wish.ownerUsername == auth.username;
    final isRealized = _wish.status == 'REALIZED';

    return Scaffold(
      backgroundColor: const Color.fromARGB(189, 255, 255, 255),
      appBar: AppBar(title: const Text('心愿详情')),
      resizeToAvoidBottomInset: true,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusChip(isRealized),
              const SizedBox(width: 8),
              _buildVisibilityChip(),
              const Spacer(),
              Text(
                _formatTime(_wish.createdAt),
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
              _buildCategoryChip(),
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

  Widget _buildStatusChip(bool isRealized) {
    final color = isRealized ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isRealized ? '已实现' : '未实现',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildVisibilityChip() {
    final isPublic = _wish.visibility == WishVisibility.public;
    final color = isPublic ? Colors.blue : Colors.purple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPublic ? '公开' : '私有',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCategoryChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _wish.category.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_wish.category.icon, size: 12, color: _wish.category.color),
          const SizedBox(width: 4),
          Text(
            _wish.category.label,
            style: TextStyle(
              fontSize: 10,
              color: _wish.category.color,
              fontWeight: FontWeight.w500,
            ),
          ),
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
    final nickname = comment.nickname.isNotEmpty ? comment.nickname : comment.username;
    final isMine = auth.isLoggedIn &&
        (comment.username == auth.username ||
            (comment.userId != null && comment.userId == auth.userId));
    final isAuthor = _wish.ownerUsername != null && comment.username == _wish.ownerUsername;

    // 自己的评论偏粉, 作者的评论偏蓝, 其他人用默认卡片色
    final Color bubbleColor;
    if (isMine) {
      bubbleColor = const Color(0xFFFFF0F6).withValues(alpha: 0.92);
    } else if (isAuthor) {
      bubbleColor = const Color(0xFFEFF7FF).withValues(alpha: 0.92);
    } else {
      bubbleColor = AppTheme.cardColor(context);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
            child: Text(
              nickname.isNotEmpty ? nickname.substring(0, 1) : '?',
              style: const TextStyle(fontSize: 13, color: Colors.pinkAccent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nickname,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMine || isAuthor) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isMine ? Colors.pinkAccent : Colors.blue)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isMine ? '我' : '作者',
                          style: TextStyle(
                            fontSize: 10,
                            color: isMine ? Colors.pinkAccent : Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                _buildCommentContent(comment.content),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      _formatCommentTime(comment.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _startReply(comment),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '回复',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isMine)
            GestureDetector(
              onTap: () => _deleteComment(comment),
              child: const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentContent(String content) {
    // 识别人工拼上的 "回复 @xxx :" 前缀, 用蓝色标出来
    final match = RegExp(r'^(回复\s*@[^:：\n]+?\s*[:：]\s*)').firstMatch(content);
    if (match == null) {
      return Text(
        content,
        style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
      );
    }

    final prefix = match.group(1)!;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(color: Colors.blue),
          ),
          TextSpan(text: content.substring(prefix.length)),
        ],
      ),
      style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
    );
  }

  Widget _buildCommentInput(AuthModel auth) {
    final serverId = _wish.serverId;

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

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatCommentTime(String raw) {
    final asInt = int.tryParse(raw);
    final dt = asInt != null
        ? DateTime.fromMillisecondsSinceEpoch(asInt)
        : DateTime.tryParse(raw);

    if (dt == null) return raw;

    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '今天 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
