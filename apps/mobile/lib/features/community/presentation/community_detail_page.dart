import 'package:bingo/core/widgets/bingo_confirm_dialog.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'dart:math';
import 'package:bingo/core/design/reference_design.dart';
import 'package:bingo/core/design/bingo_icon.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/community_widgets.dart';
import 'package:flutter/material.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:bingo/core/design/bingo_surface.dart';

class CommunityDetailPage extends StatefulWidget {
  const CommunityDetailPage(
      {required this.gateway,
      required this.shareId,
      required this.onInstalled,
      required this.onOpenCopy,
      this.onChatCopy,
      this.referenceDesign = false,
      super.key});
  final CommunityGateway gateway;
  final String shareId;
  final Future<void> Function(RoleOption) onInstalled;
  final Future<void> Function(String) onOpenCopy;
  final Future<void> Function(String)? onChatCopy;
  final bool referenceDesign;
  @override
  State<CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<CommunityDetailPage> {
  CommunityShare? _share;
  String? _installedId, _commentRequest, _commentDraft;
  bool _failed = false,
      _busy = false,
      _reacting = false,
      _sending = false,
      _commentLoading = false,
      _commentFailed = false,
      _moreComments = false;
  final _comment = TextEditingController();
  final _scroll = ScrollController();
  List<CommunityComment> _comments = [];
  CommunityEngagementGateway? get _engagement =>
      widget.gateway is CommunityEngagementGateway
          ? widget.gateway as CommunityEngagementGateway
          : null;
  @override
  void initState() {
    super.initState();
    _load();
    _loadComments();
  }

  @override
  void dispose() {
    _comment.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final share = await widget.gateway.getCommunityShare(widget.shareId);
      if (mounted) {
        setState(() {
          _share = share;
          _installedId = share.installedRoleId;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadComments({bool append = false}) async {
    if (!mounted || _engagement == null || _commentLoading) return;
    setState(() => _commentLoading = true);
    try {
      final rows = await _engagement!.listCompanionComments(widget.shareId,
          offset: append ? _comments.length : 0);
      if (mounted) {
        setState(() {
          _comments = append ? [..._comments, ...rows] : rows;
          _moreComments = rows.length == 20;
          _commentFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _commentFailed = true);
    } finally {
      if (mounted) setState(() => _commentLoading = false);
    }
  }

  Future<void> _install() async {
    if (_busy) return;
    if (_installedId != null) {
      await (widget.onChatCopy ?? widget.onOpenCopy)(_installedId!);
      return;
    }
    setState(() => _busy = true);
    try {
      final role = await widget.gateway.installCompanion(widget.shareId);
      if (mounted) setState(() => _installedId = role.id);
      await widget.onInstalled(role);
      await _load();
      if (mounted) showCenterToast(context, '已加入我的搭子，可以开始聊天了');
    } catch (_) {
      if (mounted) showCenterToast(context, '暂时无法加入，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reaction(bool like) async {
    if (_share == null || _reacting) return;
    setState(() => _reacting = true);
    try {
      final next = like
          ? await _engagement!.likeCompanion(widget.shareId, !_share!.liked)
          : await widget.gateway
              .favoriteCompanion(widget.shareId, !_share!.favorite);
      if (mounted) setState(() => _share = next);
    } catch (_) {
      if (mounted) showCenterToast(context, '操作未能保存，请重试');
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending || _engagement == null) return;
    if (_commentDraft != text) {
      _commentDraft = text;
      _commentRequest =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    }
    setState(() => _sending = true);
    try {
      await _engagement!
          .commentCompanion(widget.shareId, text, _commentRequest!);
      if (!mounted) return;
      _comment.clear();
      _commentRequest = null;
      _commentDraft = null;
      await _load();
      await _loadComments();
    } catch (_) {
      if (mounted) showCenterToast(context, '评论发送未确认，重试不会重复发布');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(CommunityComment item) async {
    try {
      await _engagement!.deleteCompanionComment(widget.shareId, item.id);
      await _load();
      await _loadComments();
    } catch (_) {
      if (mounted) showCenterToast(context, '删除失败，请重试');
    }
  }

  Future<void> _more() async {
    final share = _share;
    if (share == null) return;
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_installedId != null)
                ListTile(
                    title: const Text('编辑我的搭子'),
                    onTap: () => Navigator.pop(context, 'edit')),
              ListTile(
                  title: Text(share.favorite ? '取消收藏' : '收藏搭子'),
                  onTap: () => Navigator.pop(context, 'favorite')),
              ListTile(
                  title: Text(share.mine ? '撤回分享' : '举报分享'),
                  onTap: () => Navigator.pop(
                      context, share.mine ? 'withdraw' : 'report')),
            ])));
    if (!mounted) return;
    if (action == 'edit' && _installedId != null) {
      await widget.onOpenCopy(_installedId!);
      return;
    }
    if (action == 'favorite') {
      await _reaction(false);
      return;
    }
    if (!mounted) return;
    if (action == 'withdraw') {
      final yes = await showBingoConfirmDialog(context,
          title: '撤回这个分享？',
          message: '其他用户已经加入的搭子副本仍归他们所有。',
          confirmLabel: '撤回',
          icon: Icons.undo_rounded,
          destructive: true);
      if (yes == true) {
        try {
          await widget.gateway.withdrawCompanion(share.id);
          if (mounted) Navigator.pop(context);
        } catch (_) {
          if (mounted) showCenterToast(context, '撤回失败，请重试');
        }
      }
    }
    if (!mounted) return;
    if (action == 'report') {
      final reason = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final text in ['侵权或冒用他人内容', '不适宜内容', '垃圾广告或恶意引导'])
                  ListTile(
                      title: Text(text),
                      onTap: () => Navigator.pop(context, text))
              ])));
      if (reason != null) {
        try {
          await widget.gateway.reportCompanion(share.id, reason);
          if (mounted) showCenterToast(context, '举报已提交');
        } catch (_) {
          if (mounted) showCenterToast(context, '提交失败，请重试');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final share = _share;
    if (share == null || _failed) {
      return Scaffold(
          appBar: AppBar(title: const Text('搭子分享')),
          body: Center(
              child: _failed
                  ? TextButton(onPressed: _load, child: const Text('加载失败，点击重试'))
                  : const CircularProgressIndicator()));
    }
    final published = share.status == 'published';
    final persona = share.persona?['description'] as String?;
    final description = (persona?.trim().isNotEmpty ?? false)
        ? persona!
        : share.persona?['prompt'] as String? ?? share.introduction;
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            title: const Text('搭子分享'),
            centerTitle: true,
            backgroundColor: Colors.white,
            actions: [
              IconButton(
                  tooltip: '更多选项',
                  onPressed: _more,
                  icon: const Icon(Icons.more_horiz_rounded))
            ]),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(children: [
                  OutlinedButton.icon(
                      onPressed: published ? () => _reaction(false) : null,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      icon: Icon(
                          share.favorite
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 18),
                      label: const Text('收藏', style: TextStyle(fontSize: 13))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: FilledButton.icon(
                          onPressed:
                              _busy || (!published && _installedId == null)
                                  ? null
                                  : _install,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          icon: Icon(
                              _installedId == null
                                  ? Icons.add_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18),
                          label: Text(_busy
                              ? '正在添加…'
                              : _installedId == null
                                  ? '添加为我的搭子'
                                  : '进入聊天'))),
                ]))),
        body: SafeArea(
            bottom: false,
            child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(children: [
                    UserAvatar(username: share.authorName, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(share.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          const Text('分享了一位 AI 搭子',
                              style: TextStyle(
                                  fontSize: 10, color: BingoPalette.muted)),
                        ])),
                    Text('${share.createdAt.month}/${share.createdAt.day}',
                        style: const TextStyle(
                            fontSize: 10, color: BingoPalette.muted)),
                  ]),
                  const SizedBox(height: 24),
                  Text(
                      share.title.isEmpty
                          ? '分享我的搭子 · ${share.name}'
                          : share.title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.5)),
                  const SizedBox(height: 14),
                  Text(share.introduction,
                      style: const TextStyle(
                          fontSize: 14, height: 1.9, color: Color(0xFF566D61))),
                  const SizedBox(height: 26),
                  Text('认识一下 ${share.name}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: BingoPalette.ice,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BingoPalette.line)),
                      child: Row(children: [
                        SharedCompanionAvatar(
                            share: share, gateway: widget.gateway, size: 64),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(share.name,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Text(share.roleType ?? '陪伴搭子',
                                  style: const TextStyle(
                                      fontSize: 12, color: BingoPalette.muted)),
                              if (share.personality?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 5),
                                Text(share.personality!,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: BingoPalette.muted)),
                              ],
                            ])),
                      ])),
                  const SizedBox(height: 12),
                  CommunityTags(
                      (share.shareTags.isEmpty ? share.traits : share.shareTags)
                          .take(4)
                          .toList()),
                  _section(
                      '关于这个搭子',
                      Text(description,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.8,
                              color: BingoPalette.muted))),
                  const SizedBox(height: 16),
                  Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _metric(
                            share.liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            share.likeCount,
                            published && _engagement != null
                                ? () => _reaction(true)
                                : null,
                            BingoPalette.rose,
                            '点赞'),
                        _commentMetric(share.commentCount),
                        _metric(
                            share.favorite
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            share.favoriteCount,
                            published ? () => _reaction(false) : null,
                            BingoPalette.primaryText,
                            '收藏'),
                      ]),
                  const SizedBox(height: 16),
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: BingoPalette.ice,
                          borderRadius: BorderRadius.circular(9)),
                      child: const Text('添加后，TA 会成为你的独立搭子，和你开启新的聊天。',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.8,
                              color: BingoPalette.muted))),
                  if (share.hasImages)
                    _section(
                        '展示图片',
                        SizedBox(
                            height: 116,
                            child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: share.hasImages
                                    ? (share.imageCount > 0
                                        ? share.imageCount
                                        : 1)
                                    : 1,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, index) => ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: SizedBox(
                                        width: 116,
                                        child: share.hasImages
                                            ? SharedPostImage(
                                                share: share,
                                                gateway: widget.gateway,
                                                index: index,
                                                fallback: CompanionPortrait(
                                                    share: share,
                                                    gateway: widget.gateway))
                                            : CompanionPortrait(
                                                share: share,
                                                gateway: widget.gateway)))))),
                  _section(
                      '评论 · ${share.commentCount}',
                      Column(children: [
                        if (published && _engagement != null)
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: TextField(
                                        controller: _comment,
                                        minLines: 1,
                                        maxLines: 3,
                                        maxLength: 1000,
                                        decoration: const InputDecoration(
                                            hintText: '说点什么吧～',
                                            counterText: '',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12)))),
                                const SizedBox(width: 8),
                                TextButton(
                                    onPressed: _sending ? null : _sendComment,
                                    child: Text(_sending ? '发布中' : '发布评论')),
                              ]),
                        if (_commentLoading)
                          const Padding(
                              padding: EdgeInsets.all(12),
                              child: LinearProgressIndicator()),
                        if (_commentFailed)
                          TextButton(
                              onPressed: () => _loadComments(),
                              child: const Text('评论加载失败，点击重试')),
                        if (!_commentLoading && _comments.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('还没有评论，来聊聊这位搭子吧',
                                  style: TextStyle(
                                      color: refMuted, fontSize: 12))),
                        for (final item in _comments)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UserAvatar(
                                        username: item.authorName, size: 30),
                                    const SizedBox(width: 9),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(item.authorName,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(item.content,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.5,
                                                  color: Color(0xFF6F7F7B))),
                                        ])),
                                    if (item.mine || share.mine)
                                      IconButton(
                                          tooltip: '删除评论',
                                          onPressed: () => _deleteComment(item),
                                          icon: const Icon(Icons.close_rounded,
                                              size: 16, color: refMuted)),
                                  ])),
                        if (_moreComments)
                          TextButton(
                              onPressed: () => _loadComments(append: true),
                              child: const Text('更多评论')),
                      ])),
                ])));
  }

  Widget _section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 22),
      child: BingoSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        child,
      ])));
  Widget _metric(IconData icon, int value, VoidCallback? onTap, Color color,
          String label) =>
      Semantics(
          label: '$label $value',
          button: true,
          child: InkWell(
              onTap: _reacting ? null : onTap,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 19, color: color),
                    const SizedBox(width: 5),
                    Text('$value',
                        style: const TextStyle(fontSize: 12, color: refMuted)),
                  ]))));
  Widget _commentMetric(int count) => InkWell(
      onTap: () {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const BingoIcon(BingoSymbol.chat, size: 18),
        const SizedBox(width: 5),
        Text('$count', style: const TextStyle(fontSize: 12, color: refMuted))
      ]));
}
