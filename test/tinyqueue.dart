import 'package:rbush/rbush.dart' show TinyQueue;
import 'package:test/test.dart';
import 'dart:math' show Random;

void main() {
  final rand = Random();
  final data = [for (var i = 0; i < 100; i++) rand.nextInt(100)];
  final sorted = List.of(data);
  sorted.sort();

  test('maintains a priority queue', () {
    final queue = TinyQueue();
    for (final item in data) queue.push(item);

    expect(queue.peek(), equals(sorted.first));

    final result = <int>[];
    while (queue.isNotEmpty) result.add(queue.pop());

    expect(result, equals(sorted));
  });

  test('accepts data in constructor', () {
    final queue = TinyQueue(data);

    final result = <int>[];
    while (queue.isNotEmpty) result.add(queue.pop());

    expect(result, equals(sorted));
  });

  test('handles edge cases with few elements', () {
    final queue = TinyQueue();

    queue.push(2);
    queue.push(1);
    queue.pop();
    queue.pop();
    
    expect(() => queue.pop(), throwsStateError);

    queue.push(2);
    queue.push(1);

    expect(queue.pop(), equals(1));
    expect(queue.pop(), equals(2));
  });

  test('handles init with empty array', () {
    final queue = TinyQueue([]);
    expect(queue.data, equals([]));
  });
}
