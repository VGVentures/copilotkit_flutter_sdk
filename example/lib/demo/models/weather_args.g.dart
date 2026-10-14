// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_args.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WeatherArgs _$WeatherArgsFromJson(Map<String, dynamic> json) => $checkedCreate(
  'WeatherArgs',
  json,
  ($checkedConvert) {
    final val = WeatherArgs(city: $checkedConvert('city', (v) => v as String?));
    return val;
  },
);

Map<String, dynamic> _$WeatherArgsToJson(WeatherArgs instance) =>
    <String, dynamic>{'city': ?instance.city};
