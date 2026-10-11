import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'travel_mode.dart';

class RouteResult {
  final List<LatLng> points;
  final String encodedPolyline;
  final int distanceMeters;
  final int durationSeconds;
  final TravelMode mode;
  final String summary;

  RouteResult({
    required this.points,
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.mode,
    this.summary = '',
  });

  String get distanceText {
    if (distanceMeters < 1000) return '$distanceMeters m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get durationText {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes phút';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h giờ' : '$h giờ $m phút';
  }
}
