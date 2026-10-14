import 'package:json_annotation/json_annotation.dart';

part 'weather_args.g.dart';

/// Arguments of the `showWeather` tool.
@JsonSerializable()
class const WeatherArgs({final String? city}) {
  factory fromJson(Map<String, Object?> json) => _$WeatherArgsFromJson(json);

  /// Decodes [json], or returns `null` when it doesn't match the tool's
  /// arguments.
  static WeatherArgs? tryParse(Map<String, Object?> json) {
    try {
      return WeatherArgs.fromJson(json);
    } on CheckedFromJsonException {
      return null;
    }
  }

  Map<String, Object?> toJson() => _$WeatherArgsToJson(this);
}
