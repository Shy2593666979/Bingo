import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/community/data/community_gateway.dart';
import 'package:bingo/features/community/presentation/favorites_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway extends HttpApiGateway {
  _Gateway()
      : super(config: AppConfig(apiBaseUri: Uri.parse('http://localhost')));
  bool fail = false;
  final removed = <String>[];
  final requests = <(String, String, int)>[];
  @override
  Future<CommunityPageResult> listCommunity(
      {String query = '',
      String scope = 'all',
      String sort = 'latest',
      int offset = 0}) async {
    requests.add((scope, query, offset));
    final rows = [
      for (final (id, name) in [('one', '知夏'), ('two', '木木')])
        if (!removed.contains(id) && name.contains(query))
          CommunityShare(
              id: id,
              name: name,
              introduction: '陪你聊聊今天',
              authorName: '小满',
              createdAt: DateTime(2026),
              favorite: true,
              avatarAsset: 'colleague.png')
    ];
    return CommunityPageResult(rows.skip(offset).take(1).toList(),
        offset + 1 < rows.length ? offset + 1 : null, rows.length);
  }

  @override
  Future<CommunityShare> favoriteCompanion(String id, bool favorite) async {
    if (fail) throw Exception('offline');
    removed.add(id);
    return CommunityShare(
        id: id,
        name: '知夏',
        introduction: '',
        authorName: '小满',
        createdAt: DateTime(2026));
  }
}

void main() {
  testWidgets(
      'favorites use their own query, paginate, search and refresh after details',
      (tester) async {
    final gateway = _Gateway();
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: FavoritesPage(
            gateway: gateway,
            onOpen: (id) async {
              opened.add(id);
            })));
    await tester.pumpAndSettle();
    expect(gateway.requests.first, ('favorites', '', 0));
    expect(find.text('知夏'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('木木'), findsOneWidget);
    expect(gateway.requests.last.$3, 1);
    await tester.enterText(find.byType(TextField), '木木');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('知夏'), findsNothing);
    expect(gateway.requests.last, ('favorites', '木木', 0));
    await tester.tap(find.text('木木').last);
    await tester.pumpAndSettle();
    expect(opened, ['two']);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.close();
  });
  testWidgets(
      'failed unfavorite keeps the item; success reloads without stale offsets',
      (tester) async {
    final gateway = _Gateway()..fail = true;
    await tester.pumpWidget(MaterialApp(
        theme: buildBingoTheme(),
        home: FavoritesPage(gateway: gateway, onOpen: (_) async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消收藏 知夏'));
    await tester.pumpAndSettle();
    expect(find.text('知夏'), findsOneWidget);
    expect(gateway.removed, isEmpty);
    gateway.fail = false;
    await tester.tap(find.byTooltip('取消收藏 知夏'));
    await tester.pumpAndSettle();
    expect(find.text('知夏'), findsNothing);
    expect(find.text('木木'), findsOneWidget);
    expect(gateway.requests.last.$3, 0);
    await tester.tap(find.byTooltip('取消收藏 木木'));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏的搭子'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.close();
  });
}
