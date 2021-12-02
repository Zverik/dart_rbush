// Copyright (c) 2021 Ilya Zverev, (c) 2019 Vladimir Agafonkin.
/// Port of https://github.com/mourner/tinyqueue.
// Use of this code is governed by an ISC license, see the LICENSE file.

/// The smallest and simplest binary heap priority queue.
///
/// ```dart
/// // create an empty priority queue
/// var queue = new TinyQueue();
///
/// // add some items
/// queue.push(7);
/// queue.push(5);
/// queue.push(10);
///
/// // remove the top item
/// var top = queue.pop(); // returns 5
///
/// // return the top item (without removal)
/// top = queue.peek(); // returns 7
///
/// // get queue length
/// queue.length; // returns 2
///
/// // create a priority queue from an existing array (modifies the array)
/// queue = new TinyQueue([7, 5, 10]);
///
/// // pass a custom item comparator as a second argument
/// queue = new TinyQueue([{value: 5}, {value: 7}], function (a, b) {
/// 	return a.value - b.value;
/// });
///
/// // turn a queue into a sorted array
/// var array = [];
/// while (queue.length) array.push(queue.pop());
/// ```
class TinyQueue<T> {
  final List<T> data;
  int length;
  final Comparator<T> compare;

  /// Constructs a new queue.
  ///
  /// Adding all elements at once would be faster than using [push]
  /// for each one. If elements are not `Comparable`, specify the
  /// [compare] function.
  TinyQueue([Iterable<T>? data, Comparator<T>? compare])
      : data = data?.toList() ?? [],
        length = data?.length ?? 0,
        compare = compare ?? ((a, b) => (a as Comparable).compareTo(b)) {
    if (length > 0) {
      for (var i = (length >> 1) - 1; i >= 0; i--) {
        _down(i);
      }
    }
  }

  bool get isEmpty => length == 0;
  bool get isNotEmpty => length > 0;

  /// Adds an element to this queue.
  push(T item) {
    data.add(item);
    _up(length++);
  }

  /// Removes the smallest element from the queue and returns it.
  T pop() {
    final top = data.first;
    final bottom = data.removeLast();

    if (--length > 0) {
      data[0] = bottom;
      _down(0);
    }

    return top;
  }

  /// Returns the smallest queue element without removing it.
  T peek() => data.first;

  _up(int pos) {
    final item = data[pos];
    while (pos > 0) {
      final parent = (pos - 1) >> 1;
      final current = data[parent];
      if (compare(item, current) >= 0) break;
      data[pos] = current;
      pos = parent;
    }
    data[pos] = item;
  }

  _down(int pos) {
    final halfLength = length >> 1;
    final item = data[pos];

    while (pos < halfLength) {
      int bestChild = (pos << 1) + 1; // initially it is the left child
      final right = bestChild + 1;

      if (right < length && compare(data[right], data[bestChild]) < 0) {
        bestChild = right;
      }
      if (compare(data[bestChild], item) >= 0) break;

      data[pos] = data[bestChild];
      pos = bestChild;
    }

    data[pos] = item;
  }
}
