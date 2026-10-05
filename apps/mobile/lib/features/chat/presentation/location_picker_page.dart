import 'dart:async';
import 'dart:math' as math;
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:bingo/features/chat/presentation/widgets/companion_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ChatLocation panLocation(ChatLocation location, Offset delta, double width,
    {int zoom = 15}) {
  final scale = 256 * math.pow(2, zoom);
  final factor = 480 / width;
  final longitude = location.longitude! - delta.dx * factor / scale * 360;
  final radians = location.latitude! * math.pi / 180;
  final vertical =
      (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2;
  final value = math.pi * (1 - 2 * (vertical - delta.dy * factor / scale));
  final latitude =
      math.atan((math.exp(value) - math.exp(-value)) / 2) * 180 / math.pi;
  return ChatLocation(
      name: '地图选点',
      address: location.address,
      longitude: longitude.clamp(-180, 180),
      latitude: latitude.clamp(-85, 85),
      source: 'map');
}

double locationDistance(ChatLocation origin, ChatLocation destination) {
  const radius = 6371000.0;
  final latitude = (destination.latitude! - origin.latitude!) * math.pi / 180;
  final longitude =
      (destination.longitude! - origin.longitude!) * math.pi / 180;
  final value = math.pow(math.sin(latitude / 2), 2) +
      math.cos(origin.latitude! * math.pi / 180) *
          math.cos(destination.latitude! * math.pi / 180) *
          math.pow(math.sin(longitude / 2), 2);
  return radius * 2 * math.asin(math.sqrt(value.clamp(0, 1)));
}

class _LocationSnapshot {
  _LocationSnapshot(this.userId, this.location);
  final String userId;
  final ChatLocation location;
  final DateTime createdAt = DateTime.now();
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage(
      {required this.gateway, this.accessToken, this.userId = '', super.key});
  final LocationGateway gateway;
  final String? accessToken;
  final String userId;
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const _channel = MethodChannel('bingo/region_location');
  static const _mapChannel = MethodChannel('bingo/map_capability');
  static final _snapshots = Expando<_LocationSnapshot>();
  static bool _nativeConsent = false;
  final _search = TextEditingController();
  List<ChatLocation> _places = [];
  ChatLocation? _selected;
  ChatLocation? _current;
  ChatLocation? _center;
  bool _coarse = false;
  bool _busy = true;
  bool _locating = false;
  bool _nativeMap = false;
  bool _fromCache = false;
  String? _error;
  Timer? _debounce;
  Timer? _mapDebounce;
  int _sequence = 0;
  int _zoom = 15;
  int _retry = 0;
  Offset _drag = Offset.zero;
  double _gestureScale = 1;

  @override
  void initState() {
    super.initState();
    final cached = _snapshots[widget.gateway];
    if (cached != null &&
        cached.userId == widget.userId &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 2)) {
      _center = cached.location;
      _fromCache = true;
    }
    unawaited(_locate());
    unawaited(_prepareNative());
    unawaited(_mapChrome(true));
  }

  Future<void> _mapChrome(bool enabled) async {
    try {
      await _mapChannel
          .invokeMethod<void>('pickerOverlay', {'enabled': enabled});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _prepareNative() async {
    try {
      if (await _mapChannel.invokeMethod<bool>('available') != true ||
          !mounted) {
        return;
      }
      _nativeConsent =
          await _mapChannel.invokeMethod<bool>('consentStatus') == true;
      if (!mounted) return;
      if (!_nativeConsent) {
        final agreed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('使用高德地图'),
                  content: const Text('动态地图由高德提供。使用时，高德会处理设备和网络信息以加载地图及验证服务。'
                      '定位仍由手机系统获取，仅在你确认发送后将选中地点交给伙伴。你也可以选择暂不使用动态地图。'),
                  actions: [
                    TextButton(
                        onPressed: () =>
                            _mapChannel.invokeMethod<void>('privacyPolicy'),
                        child: const Text('查看高德隐私政策')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('暂不使用')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('同意并继续')),
                  ],
                ));
        if (agreed != true || !mounted) return;
        _nativeConsent = true;
        await _mapChannel.invokeMethod<void>('consent', {'agreed': true});
      }
      if (mounted) setState(() => _nativeMap = true);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  void dispose() {
    _sequence++;
    _debounce?.cancel();
    _mapDebounce?.cancel();
    _search.dispose();
    unawaited(_mapChrome(false));
    if (_locating) unawaited(_channel.invokeMethod<void>('cancelCoordinates'));
    super.dispose();
  }

  Future<void> _locate({bool retry = false}) async {
    _debounce?.cancel();
    _mapDebounce?.cancel();
    if (retry) _search.clear();
    final sequence = ++_sequence;
    _locating = true;
    setState(() {
      _busy = true;
      _selected = null;
      _error = null;
    });
    try {
      final coordinates = await _channel.invokeMapMethod<String, String>(
          'currentCoordinates', {'retry': retry});
      if (!mounted || sequence != _sequence) return;
      if (coordinates?['status'] != 'success') {
        setState(() => _error = coordinates?['status'] == 'denied'
            ? '定位权限未开启，仍可搜索地点发送'
            : '暂时无法定位，请重试或搜索地点');
        return;
      }
      final result = await widget.gateway.reverseLocation(
          double.parse(coordinates!['longitude']!),
          double.parse(coordinates['latitude']!),
          coordinateSystem: 'WGS84');
      if (!mounted || sequence != _sequence) return;
      final precise = coordinates['precise'] == 'true';
      final current = result.location.withSource('current',
          label: precise ? '当前位置' : '大致位置',
          precision: precise ? 'point' : 'approximate',
          accuracy: double.tryParse(coordinates['accuracy_m'] ?? ''));
      _snapshots[widget.gateway] = _LocationSnapshot(widget.userId, current);
      setState(() {
        _current = current;
        _selected = current;
        _center = current;
        _places = [current, ...result.places];
        _fromCache = false;
      });
    } on ApiException catch (error) {
      if (mounted && sequence == _sequence) {
        setState(() => _error = _serviceError(error));
      }
    } on Exception {
      if (mounted && sequence == _sequence) {
        setState(() => _error = '定位或地址解析失败，请重试或搜索地点');
      }
    } finally {
      _locating = false;
      if (mounted && sequence == _sequence) setState(() => _busy = false);
    }
  }

  String _serviceError(ApiException error) =>
      error.statusCode == 404 ? '服务器尚未开通位置功能，请联系管理员更新服务' : error.message;

  void _searchChanged(String value) {
    _debounce?.cancel();
    _mapDebounce?.cancel();
    _sequence++;
    setState(() {
      _busy = value.trim().isNotEmpty;
      _selected = null;
      _error = null;
      _places = [];
    });
    if (value.trim().isEmpty) {
      setState(() {
        _places = _current == null ? [] : [_current!];
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _find(value.trim()));
  }

  Future<void> _find(String query) async {
    final sequence = ++_sequence;
    try {
      final places = await widget.gateway
          .searchLocations(query, city: _current?.city ?? '');
      if (mounted && sequence == _sequence) setState(() => _places = places);
    } on ApiException catch (error) {
      if (mounted && sequence == _sequence) {
        setState(() => _error = _serviceError(error));
      }
    } on Exception {
      if (mounted && sequence == _sequence) {
        setState(() => _error = '地点搜索失败，请稍后重试');
      }
    } finally {
      if (mounted && sequence == _sequence) setState(() => _busy = false);
    }
  }

  void _mapMoving() {
    _sequence++;
    _mapDebounce?.cancel();
    if (_selected == null && _busy) return;
    setState(() {
      _selected = null;
      _busy = true;
      _error = null;
      _fromCache = false;
    });
  }

  void _mapIdle(ChatLocation location) {
    _mapMoving();
    _mapDebounce?.cancel();
    _mapDebounce =
        Timer(const Duration(milliseconds: 250), () => _move(location));
  }

  Future<void> _move(ChatLocation location) async {
    final sequence = ++_sequence;
    _search.clear();
    setState(() {
      _busy = true;
      _selected = null;
      _center = location;
      _error = null;
    });
    try {
      final result = await widget.gateway
          .reverseLocation(location.longitude!, location.latitude!);
      if (mounted && sequence == _sequence) {
        setState(() {
          _selected = result.location;
          _places = [result.location, ...result.places];
        });
      }
    } on ApiException catch (error) {
      if (mounted && sequence == _sequence) {
        setState(() => _error = _serviceError(error));
      }
    } on Exception {
      if (mounted && sequence == _sequence) {
        setState(() => _error = '选点地址解析失败，请重试');
      }
    } finally {
      if (mounted && sequence == _sequence) setState(() => _busy = false);
    }
  }

  void _choose(ChatLocation place) {
    FocusManager.instance.primaryFocus?.unfocus();
    _sequence++;
    _mapDebounce?.cancel();
    setState(() {
      _selected = place;
      _center = place;
      _busy = false;
      _fromCache = false;
    });
  }

  String _distance(ChatLocation place) {
    final center = _center;
    if (center == null || !center.hasCoordinates || !place.hasCoordinates) {
      return '';
    }
    final meters = locationDistance(center, place);
    return meters < 100
        ? '100米内'
        : meters < 1000
            ? '约${meters.round()}米'
            : '约${(meters / 1000).toStringAsFixed(1)}公里';
  }

  Widget _staticMap(double width, double height) {
    final center = _center;
    if (center == null) {
      return const ColoredBox(
          color: Color(0xFFEAF1EC),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, color: Color(0xFF9FB4AB), size: 44),
            SizedBox(height: 12),
            Text('正在定位，可先搜索地点', style: TextStyle(color: Color(0xFF7D918A))),
          ])));
    }
    final uri = Uri.parse(widget.gateway.locationMapUrl(center, zoom: _zoom));
    final url = uri.replace(queryParameters: {
      ...uri.queryParameters,
      'height': '${(height / width * 480).round().clamp(220, 640)}',
      'marker': 'false'
    }).toString();
    return GestureDetector(
      onScaleStart: (_) {
        _drag = Offset.zero;
        _gestureScale = 1;
      },
      onScaleUpdate: (details) {
        setState(() {
          _drag += details.focalPointDelta;
          _gestureScale = details.scale;
        });
        if (_drag.distance > 12 || (_gestureScale - 1).abs() > .15) {
          _mapMoving();
        }
      },
      onScaleEnd: (_) {
        final moved = _drag.distance > 12 || (_gestureScale - 1).abs() > .15;
        if (moved) {
          final location = panLocation(center, _drag, width, zoom: _zoom);
          setState(() {
            _zoom = (_zoom + math.log(_gestureScale.clamp(.5, 2)) / math.ln2)
                .round()
                .clamp(3, 18);
            _drag = Offset.zero;
            _gestureScale = 1;
          });
          _mapIdle(location);
        } else {
          setState(() {
            _drag = Offset.zero;
            _gestureScale = 1;
          });
        }
      },
      child: ColoredBox(
          color: const Color(0xFFEAF1EC),
          child: Transform.translate(
              offset: _drag,
              child: Image.network(
                url,
                key: ValueKey('$url:$_retry'),
                headers: {
                  if (widget.accessToken != null)
                    'Authorization': 'Bearer ${widget.accessToken}'
                },
                fit: BoxFit.fill,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: BingoPalette.mintPrimary)),
                errorBuilder: (_, error, trace) => Center(
                    child: TextButton.icon(
                        onPressed: () {
                          PaintingBinding.instance.imageCache.evict(
                              NetworkImage(url, headers: {
                            if (widget.accessToken != null)
                              'Authorization': 'Bearer ${widget.accessToken}'
                          }));
                          setState(() => _retry++);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('地图未加载，点击重试'))),
              ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final canSend = !_busy &&
        selected != null &&
        (!_coarse ||
            (selected.province.isNotEmpty && selected.district.isNotEmpty));
    return Theme(
        data: buildMintTheme(context),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
              top: false,
              child: LayoutBuilder(builder: (context, constraints) {
                final mapHeight = (constraints.maxHeight * .59)
                    .clamp(170.0,
                        math.min(560.0, constraints.maxWidth * 640 / 480))
                    .toDouble();
                final top = MediaQuery.paddingOf(context).top;
                return Column(children: [
                  SizedBox(
                      height: mapHeight,
                      child: LayoutBuilder(
                          builder: (context, mapConstraints) =>
                              Stack(fit: StackFit.expand, children: [
                                if (_nativeMap)
                                  CompanionMap(
                                    center: _center ??
                                        const ChatLocation(
                                            name: '浏览地图',
                                            address: '',
                                            longitude: 116.397,
                                            latitude: 39.909),
                                    onMoving: _mapMoving,
                                    onIdle: _mapIdle,
                                    onUnavailable: () {
                                      if (mounted) {
                                        setState(() => _nativeMap = false);
                                      }
                                    },
                                  )
                                else
                                  _staticMap(mapConstraints.maxWidth,
                                      mapConstraints.maxHeight),
                                const IgnorePointer(
                                    child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                            height: 140,
                                            width: double.infinity,
                                            child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: [
                                                  Color(0x77586960),
                                                  Color(0x00586960)
                                                ])))))),
                                if (_center != null || _nativeMap)
                                  IgnorePointer(
                                      child: Center(
                                          child: Transform.translate(
                                              offset: const Offset(0, -24),
                                              child: _LocationPin(
                                                  current: selected?.source ==
                                                      'current')))),
                                Positioned(
                                    top: top + 10,
                                    left: 12,
                                    right: 16,
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              style: TextButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12),
                                                  textStyle: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                              child: const Text('取消')),
                                          SizedBox(
                                              height: 36,
                                              child: FilledButton(
                                                  onPressed: canSend
                                                      ? () => Navigator.pop(
                                                          context,
                                                          _coarse
                                                              ? selected
                                                                  .asRegion()
                                                              : selected)
                                                      : null,
                                                  style: FilledButton.styleFrom(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 22),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          9))),
                                                  child: const Text('发送'))),
                                        ])),
                                Positioned(
                                    left: 16,
                                    bottom: 42,
                                    child: Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        elevation: 2,
                                        child: IconButton(
                                            tooltip: '重新定位',
                                            onPressed: () =>
                                                _locate(retry: true),
                                            icon: const Icon(
                                                Icons.my_location_rounded,
                                                color: BingoPalette
                                                    .mintPrimary)))),
                                if (_fromCache || _center == null)
                                  Positioned(
                                      bottom: 8,
                                      left: 72,
                                      right: 10,
                                      child: IgnorePointer(
                                          child: Text(
                                              _fromCache
                                                  ? '上次定位，仅供预览 · 正在更新'
                                                  : _nativeMap
                                                      ? '尚未定位，地图仅供浏览'
                                                      : '',
                                              textAlign: TextAlign.end,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFF5A7067))))),
                              ]))),
                  Expanded(
                      child: Material(
                          color: Colors.white,
                          child: Column(children: [
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                child: TextField(
                                  controller: _search,
                                  maxLength: 80,
                                  onChanged: _searchChanged,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                      hintText: '搜索地点',
                                      counterText: '',
                                      filled: true,
                                      fillColor: const Color(0xFFF1F5F3),
                                      prefixIcon:
                                          const Icon(Icons.search_rounded),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 10, horizontal: 14),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide.none),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: BingoPalette.mintPrimary,
                                              width: 1))),
                                )),
                            SizedBox(
                                height: 2,
                                child: _busy
                                    ? const LinearProgressIndicator(
                                        color: BingoPalette.mintPrimary,
                                        backgroundColor: BingoPalette.mintTint)
                                    : null),
                            Expanded(
                                child: ListView(
                                    padding: EdgeInsets.zero,
                                    children: [
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            20, 14, 20, 8),
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF7D918A)))),
                                  if (_busy && _places.isEmpty)
                                    Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                            _locating
                                                ? '正在获取位置…也可以直接搜索'
                                                : '正在查询地点…',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF7D918A)))),
                                  if (!_busy &&
                                      _places.isEmpty &&
                                      _error == null)
                                    const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Text('搜索一个地点，或在地图上选择位置',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF7D918A)))),
                                  for (final place in _places)
                                    Column(children: [
                                      ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 20, vertical: 3),
                                          title: Text(place.name,
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500)),
                                          subtitle: Text(
                                              [
                                                if (_distance(place).isNotEmpty)
                                                  _distance(place),
                                                place.address,
                                              ].join(' | '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF9AA8A2),
                                                  height: 1.6)),
                                          trailing: selected == place
                                              ? const Icon(Icons.check_rounded,
                                                  color:
                                                      BingoPalette.mintPrimary,
                                                  size: 23)
                                              : null,
                                          onTap: _busy
                                              ? null
                                              : () => _choose(place)),
                                      const Divider(
                                          height: 1,
                                          thickness: .5,
                                          color: Color(0xFFEDF2EF)),
                                    ]),
                                ])),
                            SizedBox(
                                height: 40,
                                child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    visualDensity: VisualDensity.compact,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('仅发送区县，不分享具体地点与坐标',
                                        style: TextStyle(fontSize: 11)),
                                    value: _coarse,
                                    onChanged: (value) => setState(
                                        () => _coarse = value ?? false))),
                            const Padding(
                                padding: EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('确认后发送给当前伙伴与模型，不实时追踪位置。',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF9AA8A2)))),
                          ]))),
                ]);
              })),
        ));
  }
}

class _LocationPin extends StatelessWidget {
  const _LocationPin({required this.current});
  final bool current;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48,
      height: 76,
      child: Stack(alignment: Alignment.center, children: [
        if (current)
          Positioned(
              bottom: 0,
              child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: const Color(0xFF53AEDE),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 6),
                      boxShadow: const [
                        BoxShadow(color: Color(0x16000000), blurRadius: 5)
                      ]))),
        const Positioned(
            top: 0,
            child: Icon(Icons.location_on_rounded,
                size: 54, color: BingoPalette.mintPrimary)),
        Positioned(
            top: 13,
            child: Container(
                width: 13,
                height: 13,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle))),
        Positioned(
            top: 42,
            child: Container(
                width: 6,
                height: 22,
                decoration: BoxDecoration(
                    color: BingoPalette.mintPrimary,
                    borderRadius: BorderRadius.circular(4)))),
      ]));
}
