import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/chat/models/chat_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationMap extends StatefulWidget {
  const LocationMap(
      {required this.location, this.url, this.accessToken, super.key});
  final ChatLocation location;
  final String? url;
  final String? accessToken;
  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  var _retry = 0;
  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 480 / 220,
      child: widget.location.hasCoordinates && widget.url != null
          ? Image.network(widget.url!,
              key: ValueKey('${widget.url}:$_retry'),
              headers: {
                if (widget.accessToken != null)
                  'Authorization': 'Bearer ${widget.accessToken}'
              },
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const ColoredBox(
                      color: BingoPalette.mintTint,
                      child: Center(
                          child: SizedBox.square(
                              dimension: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))),
              errorBuilder: (_, error, trace) => Material(
                  color: BingoPalette.mintTint,
                  child: InkWell(
                      onTap: () {
                        PaintingBinding.instance.imageCache.evict(
                            NetworkImage(widget.url!, headers: {
                          if (widget.accessToken != null)
                            'Authorization': 'Bearer ${widget.accessToken}'
                        }));
                        setState(() => _retry++);
                      },
                      child: const Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.map_outlined,
                            color: BingoPalette.mintPrimary),
                        SizedBox(height: 8),
                        Text('地图未加载，点击重试',
                            style: TextStyle(
                                fontSize: 12, color: BingoPalette.mintPrimary)),
                      ])))))
          : const ColoredBox(
              color: BingoPalette.mintTint,
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_on_outlined,
                    color: BingoPalette.mintPrimary),
                SizedBox(height: 8),
                Text('仅分享区县，不包含精确位置',
                    style: TextStyle(
                        fontSize: 12, color: BingoPalette.mintPrimary)),
              ]))));
}

class LocationCard extends StatelessWidget {
  const LocationCard(
      {required this.location, this.mapUrl, this.accessToken, super.key});
  final ChatLocation location;
  final String? mapUrl;
  final String? accessToken;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 285),
      child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: BingoPalette.line)),
          child: InkWell(
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => LocationDetailPage(
                      location: location,
                      mapUrl: mapUrl,
                      accessToken: accessToken))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(location.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 5),
                              Text(location.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.7,
                                      color: Color(0xFF7D918A))),
                            ])),
                    LocationMap(
                        location: location,
                        url: mapUrl,
                        accessToken: accessToken),
                    const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                        child: Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: BingoPalette.mintPrimary),
                          SizedBox(width: 5),
                          Text('位置 · 点击查看',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF7D918A))),
                        ])),
                  ]))));
}

class LocationDetailPage extends StatelessWidget {
  const LocationDetailPage(
      {required this.location, this.mapUrl, this.accessToken, super.key});
  final ChatLocation location;
  final String? mapUrl;
  final String? accessToken;
  Future<void> _openMap(BuildContext context) async {
    try {
      await const MethodChannel('bingo/device_tools')
          .invokeMethod<void>('openLocationMap', {
        'longitude': location.longitude,
        'latitude': location.latitude,
        'name': location.name
      });
    } on PlatformException {
      if (context.mounted) showCenterToast(context, '没有可打开的地图应用，请复制地址');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: buildMintTheme(context),
      child: Scaffold(
          appBar: AppBar(title: const Text('位置详情'), centerTitle: true),
          body: ListView(padding: const EdgeInsets.all(22), children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: LocationMap(
                    location: location, url: mapUrl, accessToken: accessToken)),
            const SizedBox(height: 20),
            Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(location.name,
                          style: const TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(location.address,
                          style: const TextStyle(
                              color: Color(0xFF7D918A), height: 1.8)),
                      const SizedBox(height: 8),
                      Text(
                          location.source == 'current'
                              ? '用户发送的当时位置，不是实时位置'
                              : '用户选择的地点，不代表当前所在位置',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF7D918A))),
                      if (location.precision == 'approximate')
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('此位置为大致定位，仅供参考',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF7D918A)))),
                      const SizedBox(height: 20),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        if (location.hasCoordinates)
                          OutlinedButton.icon(
                              onPressed: () => _openMap(context),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('打开地图')),
                        OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(
                                  text:
                                      '${location.name}\n${location.address}'));
                              if (context.mounted) {
                                showCenterToast(context, '地址已复制');
                              }
                            },
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('复制地址')),
                      ]),
                    ])),
          ])));
}
