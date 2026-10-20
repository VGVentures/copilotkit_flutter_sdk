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

  Map<String, Object?> toJson() => _$ForecastToJson(this);
}
