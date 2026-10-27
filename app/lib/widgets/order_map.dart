import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import 'common.dart';

TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'uz.supernanny.app',
      maxZoom: 19,
    );

/// Карта заказа: адрес, текущая позиция няни и пройденный путь.
class OrderMap extends StatefulWidget {
  const OrderMap({
    super.key,
    required this.destination,
    this.nanny,
    this.track = const [],
    this.nannyPhotoId,
    this.nannyName,
    this.nannySeed = 0,
  });

  final LatLng destination;
  final LatLng? nanny;
  final List<LatLng> track;
  final int? nannyPhotoId;
  final String? nannyName;
  final int nannySeed;

  @override
  State<OrderMap> createState() => _OrderMapState();
}

class _OrderMapState extends State<OrderMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _fittedWithNanny = false;

  void _fit() {
    if (!_ready) return;
    final pts = [widget.destination, ?widget.nanny];
    if (pts.length == 1) {
      _controller.move(widget.destination, 15);
    } else {
      _controller.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(70), maxZoom: 16));
      _fittedWithNanny = true;
    }
  }

  @override
  void didUpdateWidget(OrderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Подгоняем камеру, когда позиция няни появилась впервые.
    if (widget.nanny != null && !_fittedWithNanny) _fit();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.destination,
            initialZoom: 15,
            onMapReady: () {
              _ready = true;
              _fit();
            },
          ),
          children: [
            osmTiles(),
            if (widget.track.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: widget.track, strokeWidth: 5, color: kPrimary.withValues(alpha: 0.7)),
              ]),
            MarkerLayer(markers: [
              Marker(
                point: widget.destination,
                width: 46,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    color: kPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
                ),
              ),
              if (widget.nanny != null)
                Marker(
                  point: widget.nanny!,
                  width: 52,
                  height: 52,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Avatar(photoId: widget.nannyPhotoId, name: widget.nannyName, seed: widget.nannySeed, size: 46),
                  ),
                ),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 40,
          child: FloatingActionButton.small(
            heroTag: null,
            backgroundColor: Colors.white,
            foregroundColor: kPrimary,
            onPressed: _fit,
            child: const Icon(Icons.center_focus_strong_rounded),
          ),
        ),
      ],
    );
  }
}

/// Небольшая карта выбора точки: тап переносит маркер.
class PickPointMap extends StatefulWidget {
  const PickPointMap({super.key, required this.point, required this.onChanged});

  final LatLng point;
  final ValueChanged<LatLng> onChanged;

  @override
  State<PickPointMap> createState() => _PickPointMapState();
}

class _PickPointMapState extends State<PickPointMap> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: widget.point,
          initialZoom: 16,
          onTap: (_, p) => widget.onChanged(p),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          osmTiles(),
          MarkerLayer(markers: [
            Marker(
              point: widget.point,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on_rounded, color: kPink, size: 44),
            ),
          ]),
        ],
      ),
    );
  }
}
