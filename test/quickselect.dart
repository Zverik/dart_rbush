import 'package:test/test.dart';
import 'package:rbush/rbush.dart' show quickSelect;

void main() {
  test('selection', () {
    var arr = [65, 28, 59, 33, 21, 56, 22, 95, 50, 12, 90, 53, 28, 77, 39];
    quickSelect(arr, 8);
    expect(arr, equals([39, 28, 28, 33, 21, 12, 22, 50, 53, 56, 59, 65, 90, 77, 95]));
  });
}