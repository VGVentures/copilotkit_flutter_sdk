import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'forecast.g.dart';

/// Result of the `showWeather` tool: a forecast for one city.
@JsonSerializable()
class const Forecast({
  required final String city,
  required final int temperatureC,
  required final String condition,
}) {
  factory fromJson(Map<String, Object?> json) => _$ForecastFromJson(json);

  /// Decodes a JSON-encoded forecast, or returns `null` when [source] is not
  /// one (for example a cancellation or error message).
  static Forecast? tryParse(String? source) {
    try {
      return switch (jsonDecode(source ?? '')) {
        final Map<String, Object?> json => Forecast.fromJson(json),
        _ => null,
      };
    } on FormatException {
      return null;
    } on CheckedFromJsonException {
      return null;
    }
  }

  Map<String, Object?> toJson() => _$ForecastToJson(this);
}
