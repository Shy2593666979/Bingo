import 'dart:async';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> prewarmCompanionMap() async {
  try {
    await const MethodChannel('bingo/map_capability')
        .invokeMethod<void>('prewarm');
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
}

class CompanionMap extends StatefulWidget {
  const CompanionMap(
      {required this.center,
      required this.onMoving,
      required this.onIdle,
      required this.onUnavailable,
      super.key});
  final ChatLocation center;
  final VoidCallback onMoving;
  final ValueChanged<ChatLocation> onIdle;
  final VoidCallback onUnavailable;
  @override
  State<CompanionMap> createState() => _CompanionMapState();
}

class _CompanionMapState extends State<CompanionMap> {
  MethodChannel? _channel;
  Timer? _loadingTimeout;
  @override
  void didUpdateWidget(CompanionMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center.longitude != widget.center.longitude ||
        oldWidget.center.latitude != widget.center.latitude) {
      unawaited(_center());
    }
  }

  Future<void> _center() async {
    try {
      await _channel?.invokeMethod<void>('center', {
        'longitude': widget.center.longitude,
        'latitude': widget.center.latitude,
      });
    } on PlatformException {
      if (mounted) widget.onUnavailable();
    }
  }

  void _created(int id) {
    _channel = MethodChannel('bingo/map/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'moving':
          widget.onMoving();
        case 'idle':
          final position = Map<String, dynamic>.from(call.arguments as Map);
          widget.onIdle(ChatLocation(
              name: '地图选点',
              address: '正在解析地址',
              longitude: (position['longitude'] as num).toDouble(),
              latitude: (position['latitude'] as num).toDouble(),
              source: 'map'));
        case 'loaded':
          _loadingTimeout?.cancel();
        case 'unavailable':
          _loadingTimeout?.cancel();
          widget.onUnavailable();
      }
    });
    _loadingTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted) widget.onUnavailable();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _center();
    try {
      if (await _channel?.invokeMethod<bool>('ready') == true) {
        _loadingTimeout?.cancel();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      if (mounted) widget.onUnavailable();
    }
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AndroidView(
        viewType: 'bingo/companion_map',
        onPlatformViewCreated: _created,
        creationParams: {
          'longitude': widget.center.longitude,
          'latitude': widget.center.latitude,
          'privacy_agreed': true
        },
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
        },
      );
}
