import 'package:flutter/material.dart';
import 'package:bingo/core/design/companion_launch_ui.dart';

/// The reference discovery layout, mapped to Bingo's available destinations.
class CompanionHomePage extends StatelessWidget {
  const CompanionHomePage(
      {required this.onSpace,
      required this.onCommunity,
      required this.onAppearance,
      required this.onVoices,
      required this.onMessages,
      required this.onCreate,
      required this.onSearch,
      super.key});
  final VoidCallback onSpace,
      onCommunity,
      onAppearance,
      onVoices,
      onMessages,
      onCreate,
      onSearch;
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: Colors.white,
      child: SafeArea(
          bottom: false,
          child: Column(children: [
            SizedBox(
                height: 56,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: Text('发现',
                              style: CompanionLaunch.text(18,
                                  weight: FontWeight.w600))),
                      IconButton(
                          tooltip: '查找聊天',
                          onPressed: onSearch,
                          icon: const Icon(Icons.search_rounded, size: 22)),
                    ]))),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 24),
                    children: [
                  _entry('🌐', '搭子广场', onCommunity),
                  _entry('🫶', '陪伴空间', onSpace),
                  _entry('👕', '个性装扮', onAppearance),
                  _entry('🎙️', '我的音色', onVoices),
                  _entry('💬', '最近聊天', onMessages),
                  _entry('✨', '创建搭子', onCreate),
                ])),
          ])));
  Widget _entry(String picture, String title, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(children: [
                    SizedBox.square(
                        dimension: 24,
                        child: Center(
                            child: Text(picture,
                                style:
                                    const TextStyle(fontSize: 21, height: 1)))),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(title, style: CompanionLaunch.text(16))),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Color(0xFFAAAAAA)),
                  ])))));
}
