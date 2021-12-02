import 'package:test/test.dart';
import 'package:rbush/rbush.dart';

List<RBushElement> someData(int n) {
  final List<RBushElement> data = [];
  for (double i = 0; i < n; i++) {
    data.add(RBushElement(minX: i, minY: i, maxX: i, maxY: i));
  }
  return data;
}

RBushElement listToBBox(List<double> list) {
  return RBushElement(minX: list[0], minY: list[1], maxX: list[2], maxY: list[3]);
}

final data = <List<double>>[
  [0, 0, 0, 0], [10, 10, 10, 10], [20, 20, 20, 20], [25, 0, 25, 0], [35, 10, 35, 10],
  [45, 20, 45, 20], [0, 25, 0, 25], [10, 35, 10, 35], [20, 45, 20, 45], [25, 25, 25, 25],
  [35, 35, 35, 35], [45, 45, 45, 45], [50, 0, 50, 0], [60, 10, 60, 10], [70, 20, 70, 20],
  [75, 0, 75, 0], [85, 10, 85, 10], [95, 20, 95, 20], [50, 25, 50, 25], [60, 35, 60, 35],
  [70, 45, 70, 45], [75, 25, 75, 25], [85, 35, 85, 35], [95, 45, 95, 45], [0, 50, 0, 50],
  [10, 60, 10, 60], [20, 70, 20, 70], [25, 50, 25, 50], [35, 60, 35, 60], [45, 70, 45, 70],
  [0, 75, 0, 75], [10, 85, 10, 85], [20, 95, 20, 95], [25, 75, 25, 75], [35, 85, 35, 85],
  [45, 95, 45, 95], [50, 50, 50, 50], [60, 60, 60, 60], [70, 70, 70, 70], [75, 50, 75, 50],
  [85, 60, 85, 60], [95, 70, 95, 70], [50, 75, 50, 75], [60, 85, 60, 85], [70, 95, 70, 95],
  [75, 75, 75, 75], [85, 85, 85, 85], [95, 95, 95, 95],
].map((list) => listToBBox(list)).toList();

final emptyData = <List<double>>[
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
  [double.negativeInfinity, double.negativeInfinity, double.infinity, double.infinity],
].map((list) => listToBBox(list));

class MyItem {
  final double minLng;
  final double minLat;
  final double maxLng;
  final double maxLat;

  const MyItem(
      {required this.minLng,
      required this.minLat,
      required this.maxLng,
      required this.maxLat});

  @override
  bool operator ==(Object other) {
    if (other is! MyItem) return false;
    return minLng == other.minLng && minLat == other.minLat
        && maxLng == other.maxLng && maxLat == other.maxLat;
  }
}

void main() {
  test('allows custom formats by overriding some methods', () {
    final tree = RBushBase<MyItem>(
      toBBox: (item) => RBushBox(
        minX: item.minLng,
        minY: item.minLat,
        maxX: item.maxLng,
        maxY: item.maxLat,
      ),
      getMinX: (item) => item.minLng,
      getMinY: (item) => item.minLat,
    );
    expect(tree.toBBox(MyItem(minLng: 1, minLat: 2, maxLng: 3, maxLat: 4)),
        equals(RBushBox(minX: 1, minY: 2, maxX: 3, maxY: 4)));
  });

  test('constructor uses 9 max entries by default', () {
    final tree = RBush().load(someData(9));
    expect(tree.data.height, equals(1));

    final tree2 = RBush().load(someData(10));
    expect(tree2.data.height, equals(2));
  });

  test('#toBBox, #compareMinX, #compareMinY can be overriden to allow custom data structures', () {
    final tree = RBushBase<MyItem>(
      maxEntries: 4,
      toBBox: (item) => RBushBox(
        minX: item.minLng,
        minY: item.minLat,
        maxX: item.maxLng,
        maxY: item.maxLat,
      ),
      getMinX: (item) => item.minLng,
      getMinY: (item) => item.minLat,
    );

    const data = [
      MyItem(minLng: -115, minLat: 45, maxLng: -105, maxLat: 55),
      MyItem(minLng: 105, minLat: 45, maxLng: 115, maxLat: 55),
      MyItem(minLng: 105, minLat: -55, maxLng: 115, maxLat: -45),
      MyItem(minLng: -115, minLat: -55, maxLng: -105, maxLat: -45),
    ];

    tree.load(data);

    expect(
      tree.search(RBushBox(minX: -180, minY: -90, maxX: 180, maxY: 90)),
      unorderedEquals([
        MyItem(minLng: -115, minLat: 45, maxLng: -105, maxLat: 55),
        MyItem(minLng: 105, minLat: 45, maxLng: 115, maxLat: 55),
        MyItem(minLng: 105, minLat: -55, maxLng: 115, maxLat: -45),
        MyItem(minLng: -115, minLat: -55, maxLng: -105, maxLat: -45),
      ]),
    );

    expect(
      tree.search(RBushBox(minX: -180, minY: -90, maxX: 0, maxY: 90)),
      unorderedEquals([
        MyItem(minLng: -115, minLat: 45, maxLng: -105, maxLat: 55),
        MyItem(minLng: -115, minLat: -55, maxLng: -105, maxLat: -45),
      ]),
    );

    expect(
      tree.search(RBushBox(minX: 0, minY: -90, maxX: 180, maxY: 90)),
      unorderedEquals([
        MyItem(minLng: 105, minLat: 45, maxLng: 115, maxLat: 55),
        MyItem(minLng: 105, minLat: -55, maxLng: 115, maxLat: -45),
      ]),
    );

    expect(
      tree.search(RBushBox(minX: -180, minY: 0, maxX: 180, maxY: 90)),
      unorderedEquals([
        MyItem(minLng: -115, minLat: 45, maxLng: -105, maxLat: 55),
        MyItem(minLng: 105, minLat: 45, maxLng: 115, maxLat: 55),
      ]),
    );

    expect(
      tree.search(RBushBox(minX: -180, minY: -90, maxX: 180, maxY: 0)),
      unorderedEquals([
        MyItem(minLng: 105, minLat: -55, maxLng: 115, maxLat: -45),
        MyItem(minLng: -115, minLat: -55, maxLng: -105, maxLat: -45),
      ]),
    );
  });

  test('#load bulk-loads the given data given max node entries and forms a proper search tree', () {
    final tree = RBush(4).load(data);
    expect(tree.all(), unorderedEquals(data));
  });

  test('#load uses standard insertion when given a low number of items', () {
    final tree = RBush(8).load(data).load(data.sublist(0, 3));
    final tree2 = RBush(8).load(data);

    tree2.insert(data[0]);
    tree2.insert(data[1]);
    tree2.insert(data[2]);

    expect(tree.data, equals(tree2.data));
  });

  test('#load does nothing if loading empty data', () {
    final tree = RBush().load([]);
    expect(tree.data, equals(RBush().data));
  });

  test('#load handles the insertion of maxEntries + 2 empty bboxes', () {
    final tree = RBush(4).load(emptyData);
    expect(tree.data.height, equals(2));
    expect(tree.all(), unorderedEquals(emptyData));
  });

  test('#insert handles the insertion of maxEntries + 2 empty bboxes', () {
    final tree = RBush(4);
    for (final element in emptyData) { tree.insert(element); }

    expect(tree.data.height, equals(2), reason: 'height');
    expect(tree.all(), unorderedEquals(emptyData), reason: 'all');
    expect(tree.data.children[0].childrenLength, equals(4), reason: 'children 0');
    expect(tree.data.children[1].childrenLength, equals(2), reason: 'children 1');
  });

  test('#load properly splits tree root when merging trees of the same height', () {
    final tree = RBush(4).load(data).load(data);
    expect(tree.data.height, equals(4));
    expect(tree.all(), unorderedEquals(data + data));
  });

  test('#load properly merges data of smaller or bigger tree heights', () {
    final smaller = someData(10);
    final tree1 = RBush(4).load(data).load(smaller);
    final tree2 = RBush(4).load(smaller).load(data);

    expect(tree1.data.height, equals(tree2.data.height));
    expect(tree1.all(), unorderedEquals(data + smaller));
    expect(tree2.all(), unorderedEquals(data + smaller));
  });

  test('#search finds matching points in the tree given a bbox', () {
    final tree = RBush(4).load(data);
    final result = tree.search(RBushBox(minX: 40, minY: 20, maxX: 80, maxY: 70));

    expect(result, unorderedEquals(<List<double>>[
      [70,20,70,20],[75,25,75,25],[45,45,45,45],[50,50,50,50],[60,60,60,60],[70,70,70,70],
      [45,20,45,20],[45,70,45,70],[75,50,75,50],[50,25,50,25],[60,35,60,35],[70,45,70,45],
    ].map((list) => listToBBox(list))));
  });

  test('#collides returns true when search finds matching points', () {
    final tree = RBush(4).load(data);
    final result = tree.collides(RBushBox(minX: 40, minY: 20, maxX: 80, maxY: 70));

    expect(result, isTrue);
  });

  test('#search returns an empty array if nothing found', () {
    final result = RBush(4).load(data).search(RBushBox(minX: 200, minY: 200, maxX: 200, maxY: 200));
    expect(result, equals([]));
  });

  test('#collides returns false if nothing found', () {
    final result = RBush(4).load(data).collides(RBushBox(minX: 200, minY: 200, maxX: 200, maxY: 200));
    expect(result, isFalse);
  });

  test('#all returns all points in the tree', () {
    final tree = RBush(4).load(data);
    final result = tree.all();

    expect(result, unorderedEquals(data));
    expect(tree.search(RBushBox(minX: 0, minY: 0, maxX: 100, maxY: 100)), unorderedEquals(data));
  });

  test('#insert adds an item to an existing tree correctly', () {
    final items = <List<double>>[
      [0, 0, 0, 0],
      [1, 1, 1, 1],
      [2, 2, 2, 2],
      [3, 3, 3, 3],
      [1, 1, 2, 2],
    ].map((list) => listToBBox(list)).toList();

    final tree = RBush(4).load(items.sublist(0, 3));

    tree.insert(items[3]);
    expect(tree.data.height, equals(1), reason: 'height 3');
    expect(tree.all(), unorderedEquals(items.sublist(0, 4)), reason: 'all 3');

    tree.insert(items[4]);
    expect(tree.data.height, equals(2), reason: 'height 4');
    expect(tree.all(), unorderedEquals(items), reason: 'all 4');
  });

  test('#insert forms a valid tree if items are inserted one by one', () {
    final tree = RBush(4);

    for (var i = 0; i < data.length; i++) {
      tree.insert(data[i]);
    }

    final tree2 = RBush(4).load(data);

    expect((tree.data.height - tree2.data.height).abs(), lessThanOrEqualTo(1));
    expect(tree.all(), unorderedEquals(tree2.all()));
  });

  test('#remove removes items correctly', () {
    final tree = RBush(4).load(data);
    final len = data.length;

    tree.remove(data[0]);
    tree.remove(data[1]);
    tree.remove(data[2]);

    tree.remove(data[len - 1]);
    tree.remove(data[len - 2]);
    tree.remove(data[len - 3]);

    expect(data.sublist(3, len - 3), unorderedEquals(tree.all()));
  });

  test('#remove does nothing if nothing found', () {
    final removed = RBush().load(data);
    removed.remove(listToBBox([13, 13, 13, 13]));

    expect(RBush().load(data).data, equals(removed.data));
  });

  test('#remove brings the tree to a clear state when removing everything one by one', () {
    final tree = RBush(4).load(data);

    for (final item in data) tree.remove(item);

    expect(tree.data, equals(RBush(4).data));
  });

  test('#clear should clear all the data in the tree', () {
    final tree = RBush(4).load(data);
    tree.clear();

    expect(tree.data, equals(RBush(4).data));
  });
}
