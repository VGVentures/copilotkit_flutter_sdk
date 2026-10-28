import 'package:api_summary/api_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('api.txt matches the public API', expectApiSummaryClean);
}
