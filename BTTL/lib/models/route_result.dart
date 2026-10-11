import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteResult {
  final List<LatLng> points;
  final String distanceText;
  final String durationText;

  RouteResult({
    required this.points,
    required this.distanceText,
    required this.durationText,
  });
}
