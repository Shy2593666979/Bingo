import 'package:flutter/material.dart';

class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key});
  final int count;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '$count条未读消息',
      child: Container(
          constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F),
              borderRadius: BorderRadius.circular(99)),
          child: Text(count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Colors.white,
                  fontWeight: FontWeight.w600))));
}
