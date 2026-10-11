import 'package:flutter/material.dart';

enum TravelMode { car, motorbike, walk }

extension TravelModeInfo on TravelMode {
  String get label {
    switch (this) {
      case TravelMode.car:
        return 'Ô tô';
      case TravelMode.motorbike:
        return 'Xe máy';
      case TravelMode.walk:
        return 'Đi bộ';
    }
  }

  IconData get icon {
    switch (this) {
      case TravelMode.car:
        return Icons.directions_car;
      case TravelMode.motorbike:
        return Icons.two_wheeler;
      case TravelMode.walk:
        return Icons.directions_walk;
    }
  }

  Color get color {
    switch (this) {
      case TravelMode.car:
        return Colors.blue;
      case TravelMode.motorbike:
        return Colors.deepPurple;
      case TravelMode.walk:
        return Colors.green;
    }
  }

  String get directionsMode {
    switch (this) {
      case TravelMode.car:
      case TravelMode.motorbike:
        return 'driving';
      case TravelMode.walk:
        return 'walking';
    }
  }

  String get routesMode {
    switch (this) {
      case TravelMode.car:
        return 'DRIVE';
      case TravelMode.motorbike:
        return 'TWO_WHEELER';
      case TravelMode.walk:
        return 'WALK';
    }
  }

  static TravelMode fromName(String name) {
    return TravelMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => TravelMode.car,
    );
  }
}
