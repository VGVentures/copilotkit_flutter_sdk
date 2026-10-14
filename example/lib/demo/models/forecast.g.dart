// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forecast.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Forecast _$ForecastFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Forecast',
  json,
  ($checkedConvert) {
    final val = Forecast(
      city: $checkedConvert('city', (v) => v as String),
      temperatureC: $checkedConvert('temperatureC', (v) => (v as num).toInt()),
      condition: $checkedConvert('condition', (v) => v as String),
    );
    return val;
  },
);

Map<String, dynamic> _$ForecastToJson(Forecast instance) => <String, dynamic>{
  'city': instance.city,
  'temperatureC': instance.temperatureC,
  'condition': instance.condition,
};
