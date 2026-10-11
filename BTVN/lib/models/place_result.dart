import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceResult {
  final String name;
  final String address;
  final LatLng location;

  PlaceResult({
    required this.name,
    required this.address,
    required this.location,
  });
}
