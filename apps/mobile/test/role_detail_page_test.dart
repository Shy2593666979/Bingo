import 'dart:convert';

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_message.dart';
import 'package:bingo/features/roles/presentation/role_detail_page.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:bingo/shared/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DetailGateway implements RoleGateway, ConversationGateway {
  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async => const [
        ChatMessage(id: 'user', role: ChatRole.user, content: '你好'),
        ChatMessage(
            id: 'assistant',
            role: ChatRole.assistant,
            content: '你好呀，今天过得怎么样？无论有什么开心的事情或者烦恼，都可以慢慢和我说。'),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final custom in [false, true]) {
    testWidgets('recent conversation uses the user avatar: custom=$custom',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const avatar =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDVsAAAAASUVORK5CYII=';
      await tester.pumpWidget(MaterialApp(
          theme: buildBingoTheme(),
          home: RoleDetailPage(
              role: const RoleOption(
                  id: 'role',
                  name: '女朋友',
                  builtin: true,
                  conversationId: 'conversation'),
              gateway: DetailGateway(),
              userAvatarData: custom ? avatar : null,
              onChat: (_) async {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('你好'));
      expect(find.text('最近对话'), findsOneWidget);
      expect(find.text('你们的最近对话'), findsNothing);
      expect(find.byType(UserAvatar), findsOneWidget);
      final image = tester.widget<Image>(find.descendant(
          of: find.byType(UserAvatar), matching: find.byType(Image)));
      if (custom) {
        expect((image.image as MemoryImage).bytes, base64Decode(avatar));
      } else {
        expect((image.image as AssetImage).assetName,
            'assets/images/bingo_logo.png');
      }
      expect(find.byType(AssistantAvatar), findsNWidgets(2));
      final userRow = tester.widget<Row>(
          find.ancestor(of: find.text('你好'), matching: find.byType(Row)).first);
      expect(userRow.mainAxisAlignment, MainAxisAlignment.end);
      final assistantRow = tester.widget<Row>(find
          .ancestor(
              of: find.text('你好呀，今天过得怎么样？无论有什么开心的事情或者烦恼，都可以慢慢和我说。'),
              matching: find.byType(Row))
          .first);
      expect(assistantRow.mainAxisAlignment, MainAxisAlignment.start);
      expect(tester.getTopLeft(find.byType(UserAvatar)).dx,
          greaterThan(tester.getTopRight(find.text('你好')).dx));
      final shortBubble = tester.getSize(find
          .ancestor(of: find.text('你好'), matching: find.byType(Container))
          .first);
      final longBubble = tester.getSize(find
          .ancestor(
              of: find.text('你好呀，今天过得怎么样？无论有什么开心的事情或者烦恼，都可以慢慢和我说。'),
              matching: find.byType(Container))
          .first);
      expect(shortBubble.width, lessThan(140));
      expect(shortBubble.width, lessThan(longBubble.width));
      expect(longBubble.height, greaterThan(shortBubble.height));
      expect(tester.takeException(), isNull);
    });
  }
}
