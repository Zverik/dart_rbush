// Copyright (c) 2021 Ilya Zverev, (c) 2020 Vladimir Agafonkin.
// Port of https://github.com/mourner/rbush and https://github.com/mourner/rbush-knn.
// Use of this code is governed by an ISC license, see the LICENSE file.
import 'dart:math' show min, max, log, pow, sqrt, Random;
import 'package:collection/collection.dart';

import 'quickselect.dart';
import 'tinyqueue.dart';

typedef MinXYGetter<T> = double Function(T item);

/// RBush — a high-performance R-tree-based 2D spatial index for points and rectangles.
class RBushBase<T> {
  final int _minEntries;
  final int _maxEntries;
  _RBushNode<T> data;

  final RBushBox Function(T item) toBBox;
  final MinXYGetter<T> getMinX;
  final MinXYGetter<T> getMinY;

  /// Constructs a new r-tree with items of type [T].
  /// Each leaf would have at most [maxEntries] items.
  ///
  /// Use [load] to bulk load items into this tree, or
  /// [insert] to append one by one. After that use [search]
  /// and [knn] for searching inside the tree.
  ///
  /// Specify [toBBox], [getMinX], and [getMinY] to extract
  /// needed information from objects of type [T]. Alternatively,
  /// see [RBush] class for a simpler option.
  RBushBase(
      {int maxEntries = 9,
      required this.toBBox,
      required this.getMinX,
      required this.getMinY})
      : _maxEntries = max(4, maxEntries),
        _minEntries = max(2, (max(4, maxEntries) * 0.4).ceil()),
        data = _RBushNode<T>([]);

  /// Returns all items inside this tree.
  List<T> all() => _all(data, []);

  /// Looks for all items that intersect with [bbox].
  List<T> search(RBushBox bbox) {
    _RBushNode<T> node = data;
    final List<T> result = [];

    if (!bbox.intersects(node)) return result;

    final List<_RBushNode<T>> nodesToSearch = [];

    while (true) {
      if (node.leaf) {
        for (final child in node.leafChildren) {
          if (bbox.intersects(toBBox(child))) {
            result.add(child);
          }
        }
      } else {
        for (final child in node.children) {
          if (bbox.intersects(child)) {
            if (bbox.contains(child)) {
              _all(child, result);
            } else {
              nodesToSearch.add(child);
            }
          }
        }
      }
      if (nodesToSearch.isEmpty) break;
      node = nodesToSearch.removeLast();
    }

    return result;
  }

  /// Tests if any items intersect with [bbox].
  /// Use [search] if you need the list.
  bool collides(RBushBox bbox) {
    _RBushNode<T> node = data;

    if (!bbox.intersects(node)) return false;

    final List<_RBushNode<T>> nodesToSearch = [];

    while (true) {
      if (node.leaf) {
        for (final child in node.leafChildren) {
          if (bbox.intersects(toBBox(child))) {
            return true;
          }
        }
      } else {
        for (final child in node.children) {
          if (bbox.intersects(child)) {
            if (bbox.contains(child)) return true;
            nodesToSearch.add(child);
          }
        }
      }
      if (nodesToSearch.isEmpty) break;
      node = nodesToSearch.removeLast();
    }

    return false;
  }

  /// Bulk loads items into this r-tree.
  /// This method returns `this` to allow for this chaining:
  /// `RBushBase().load([...])`
  RBushBase<T> load(Iterable<T> items) {
    if (items.isEmpty) return this;

    if (items.length < _minEntries) {
      for (final item in items) insert(item);
      return this;
    }

    // recursively build the tree with the given data from scratch using OMT algorithm
    _RBushNode<T> node = _build(List.of(items), 0, items.length - 1, 0);

    if (data.childrenLength == 0) {
      // save as is if tree is empty
      data = node;
    } else if (data.height == node.height) {
      // split root if trees have the same height
      _splitRoot(data, node);
    } else {
      if (data.height < node.height) {
        // swap trees if inserted one is bigger
        final tmpNode = data;
        data = node;
        node = tmpNode;
      }

      // insert the small tree into the large tree at appropriate level
      _insert(data.height - node.height - 1, inode: node);
    }

    return this;
  }

  /// Inserts a single item into the tree.
  insert(T item) {
    _insert(data.height - 1, item: item);
  }

  /// Removes all items from the tree.
  clear() {
    data = _RBushNode<T>([]);
  }

  /// Removes a single item from the tree.
  /// Does nothing if the item is not there.
  remove(T? item) {
    if (item == null) return;

    _RBushNode<T>? node = data;
    final bbox = toBBox(item);
    List<_RBushNode<T>> path = [];
    List<int> indexes = [];
    int i = 0;
    _RBushNode<T>? parent;
    bool goingUp = false;

    // depth-first iterative tree traversal
    while (node != null || path.isNotEmpty) {
      if (node == null) {
        // go up
        node = path.removeLast();
        parent = path.isEmpty ? null : path.last;
        i = indexes.removeLast();
        goingUp = true;
      }

      if (node.leaf) {
        // check current node
        final index = node.leafChildren.indexOf(item);
        if (index != -1) {
          // item found, remove the item and condense tree upwards
          node.leafChildren.removeAt(index);
          path.add(node);
          _condense(path);
          return;
        }
      }

      if (!goingUp && !node.leaf && node.contains(bbox)) {
        // go down
        path.add(node);
        indexes.add(i);
        i = 0;
        parent = node;
        node = node.children.first;
      } else if (parent != null) {
        // go right
        i++;
        node = i >= parent.children.length ? null : parent.children[i];
        goingUp = false;
      } else {
        // nothing found
        node = null;
      }
    }
  }

  /// K-nearest neighbors search.
  ///
  /// For a given ([x], [y]) location, returns [k] nearest items,
  /// sorted by distance to their bounding boxes.
  ///
  /// Use [maxDistance] to filter by distance as well.
  /// Use [predicate] function to filter by item properties.
  List<T> knn(double x, double y, int k,
      {bool Function(T item)? predicate, double? maxDistance}) {
    final List<T> result = [];
    if (k <= 0) return result;

    _RBushNode<T> node = data;
    final queue = TinyQueue<_KnnElement<T>>([]);

    while (true) {
      if (node.leaf) {
        for (final child in node.leafChildren) {
          final dist = toBBox(child).distanceSq(x, y);
          if (maxDistance == null || dist <= maxDistance * maxDistance) {
            queue.push(_KnnElement(item: child, dist: dist));
          }
        }
      } else {
        for (final child in node.children) {
          final dist = child.distanceSq(x, y);
          if (maxDistance == null || dist <= maxDistance * maxDistance) {
            queue.push(_KnnElement(node: child, dist: dist));
          }
        }
      }

      while (queue.isNotEmpty && queue.peek().item != null) {
        T candidate = queue.pop().item!;
        if (predicate == null || predicate(candidate)) {
          result.add(candidate);
        }
        if (result.length == k) return result;
      }

      if (queue.isEmpty) break;
      if (queue.peek().node == null) break;
      node = queue.pop().node!;
    }

    return result;
  }

  /// K-nearest neighbors search.
  ///
  /// Given distance() function, returns [k] nearest items,
  /// sorted by distance to items.
  ///
  /// Use [distance] to filter by distance. It gets an item and its
  /// bounding box for the input, with null item for non leaf node.
  /// [distance] returns distance to the item or bbox or null if
  /// distance is not within acceptable range.
  /// Use [predicate] function to filter by item properties.
  List<T> knnGeneric(int k, {
    required double? Function(T? item, RBushBox bbox) distance,
    bool Function(T item, double dist)? predicate,
  }) {
    final List<T> result = [];
    if (k <= 0) return result;

    _RBushNode<T> node = data;
    final queue = TinyQueue<_KnnElement<T>>([]);

    while (true) {
      if (node.leaf) {
        for (final child in node.leafChildren) {
          final dist = distance(child, toBBox(child));
          if (dist != null) {
            queue.push(_KnnElement(item: child, dist: dist));
          }
        }
      } else {
        for (final child in node.children) {
          final dist = distance(null, child);
          if (dist != null) {
            queue.push(_KnnElement(node: child, dist: dist));
          }
        }
      }

      while (queue.isNotEmpty && queue.peek().item != null) {
        final elem = queue.pop();
        // ignore: null_check_on_nullable_type_parameter
        final candidate = elem.item!;
        if (predicate == null || predicate(candidate, elem.dist)) {
          result.add(candidate);
        }
        if (result.length == k) return result;
      }

      if (queue.isEmpty) break;
      if (queue.peek().node == null) break;
      node = queue.pop().node!;
    }

    return result;
  }

  List<T> _all(_RBushNode<T> node, List<T> result) {
    final List<_RBushNode<T>> nodesToSearch = [];
    while (true) {
      if (node.leaf) {
        result.addAll(node.leafChildren);
      } else {
        nodesToSearch.addAll(node.children);
      }
      if (nodesToSearch.isEmpty) break;
      node = nodesToSearch.removeLast();
    }
    return result;
  }

  _RBushNode<T> _build(List<T> items, int left, int right, int height) {
    final N = right - left + 1;
    var M = _maxEntries;
    _RBushNode<T> node;

    if (N <= M) {
      // reached leaf level; return leaf
      node = _RBushNode([], items.sublist(left, right + 1));
      _calcBBox(node);
      return node;
    }

    if (height == 0) {
      // target height of the bulk-loaded tree
      height = (log(N) / log(M)).ceil();

      // target number of root entries to maximize storage utilization
      M = (N / pow(M, height - 1)).ceil();
    }

    node = _RBushNode([]);
    node.leaf = false;
    node.height = height;

    // split the items into M mostly square tiles

    final N2 = (N.toDouble() / M).ceil();
    final N1 = N2 * sqrt(M).ceil();

    _multiSelect(items, left, right, N1, getMinX);

    for (int i = left; i <= right; i += N1) {
      final right2 = min(i + N1 - 1, right);

      _multiSelect(items, i, right2, N2, getMinY);

      for (int j = i; j <= right2; j += N2) {
        final right3 = min(j + N2 - 1, right2);

        // pack each entry recursively
        node.children.add(_build(items, j, right3, height - 1));
      }
    }
    _calcBBox(node);
    return node;
  }

  void test() {
    var ri = Random();
    int n = 100000;
    for (var i = 0; i < n; i++) {
      double lat = ri.nextDouble() * 180 - 90;
      double lng = ri.nextDouble() * 360 - 180;
      insert(RBushElement.fromList([lat, lng, lat, lng], null) as T);
    }
    _RBushNode node = data;
    final List<_RBushNode> nodesToSearch = [];
    final observations = <num>[];
    while (true) {
      observations.add(log((node.maxX - node.minX) / (node.maxY - node.minY)));
      // print(
      //     "stats: ${node.height} ${node.leaf ? node.leafChildren.length : node.children.length} ${node.minX} ${node.minY} ${node.maxX} ${node.maxY}");
      if (node.leaf) {
      } else {
        nodesToSearch.addAll(node.children);
      }
      if (nodesToSearch.isEmpty) break;
      node = nodesToSearch.removeLast();
    }
    assert(observations.average.abs() < 0.1);
  }

  _RBushNode<T> _chooseSubtree(
      RBushBox bbox, _RBushNode<T> node, int level, List<_RBushNode<T>> path) {
    while (true) {
      path.add(node);

      if (node.leaf || path.length - 1 == level) break;

      var minArea = double.infinity;
      var minEnlargement = double.infinity;
      _RBushNode<T>? targetNode;

      // no leaves here
      for (final child in node.children) {
        final area = child.area;
        final enlargement = bbox.enlargedArea(child) - area;

        // choose entry with the least area enlargement
        if (enlargement < minEnlargement) {
          minEnlargement = enlargement;
          minArea = area < minArea ? area : minArea;
          targetNode = child;
        } else if (enlargement == minEnlargement) {
          // otherwise choose one with the smallest area
          if (area < minArea) {
            minArea = area;
            targetNode = child;
          }
        }
      }

      node = targetNode ?? node.children.first;
    }

    return node;
  }

  _insert(int level, {T? item, _RBushNode<T>? inode}) {
    RBushBox bbox = item != null ? toBBox(item) : inode!;
    final List<_RBushNode<T>> insertPath = [];

    // find the best node for accommodating the item, saving all nodes along the path too
    final node = _chooseSubtree(bbox, data, level, insertPath);

    // put the item into the node
    if (item != null) {
      node.leafChildren.add(item);
    } else {
      node.children.add(inode!);
    }
    node.extend(bbox);

    // split on node overflow; propagate upwards if necessary
    while (level >= 0) {
      if (insertPath[level].childrenLength > _maxEntries) {
        _split(insertPath, level);
        level--;
      } else {
        break;
      }
    }

    // adjust bboxes along the insertion path
    _adjustParentBBoxes(bbox, insertPath, level);
  }

  /// split overflowed node into two
  _split(List<_RBushNode<T>> insertPath, int level) {
    final node = insertPath[level];
    final M = node.childrenLength;
    final m = _minEntries;

    _chooseSplitAxis(node, m, M);

    final splitIndex = _chooseSplitIndex(node, m, M);

    _RBushNode<T> newNode;
    if (node.leaf) {
      newNode = _RBushNode<T>([], node.leafChildren.sublist(splitIndex));
      node.leafChildren.removeRange(splitIndex, node.leafChildren.length);
    } else {
      newNode = _RBushNode(node.children.sublist(splitIndex));
      node.children.removeRange(splitIndex, node.children.length);
    }
    newNode.height = node.height;

    _calcBBox(node);
    _calcBBox(newNode);

    if (level > 0) {
      insertPath[level - 1].children.add(newNode);
    } else {
      _splitRoot(node, newNode);
    }
  }

  /// Split root node
  _splitRoot(_RBushNode<T> node, _RBushNode<T> newNode) {
    data = _RBushNode<T>([node, newNode]);
    data.height = node.height + 1;
    _calcBBox(data);
  }

  int _chooseSplitIndex(_RBushNode<T> node, m, M) {
    int? index;
    double minOverlap = double.infinity;
    double minArea = double.infinity;

    for (var i = m; i <= M - m; i++) {
      final bbox1 = _distBBox(node, 0, i);
      final bbox2 = _distBBox(node, i, M);

      final overlap = bbox1.intersectionArea(bbox2);
      final area = bbox1.area + bbox2.area;

      // choose distribution with minimum overlap
      if (overlap < minOverlap) {
        minOverlap = overlap;
        index = i;

        minArea = area < minArea ? area : minArea;
      } else if (overlap == minOverlap) {
        // otherwise choose distribution with minimum area
        if (area < minArea) {
          minArea = area;
          index = i;
        }
      }
    }

    return index ?? M - m;
  }

  _chooseSplitAxis(node, m, M) {
    final xMargin = _addDistMargin(node, m, M, true);
    final yMargin = _addDistMargin(node, m, M, false);

    // if total distributions margin value is minimal for x, sort by minX,
    // otherwise it's already sorted by minY
    if (xMargin < yMargin) _sortChildrenBy(node, true);
  }

  _sortChildrenBy(_RBushNode<T> node, bool sortByMinX) {
    final getter = sortByMinX ? getMinX : getMinY;
    if (sortByMinX) {
      node.children.sort((a, b) => a.minX.compareTo(b.minX));
    } else {
      node.children.sort((a, b) => a.minY.compareTo(b.minY));
    }
    node.leafChildren.sort((a, b) => getter(a).compareTo(getter(b)));
  }

  double _addDistMargin(_RBushNode<T> node, int m, int M, bool sortByMinX) {
    _sortChildrenBy(node, sortByMinX);

    final leftBBox = _distBBox(node, 0, m);
    final rightBBox = _distBBox(node, M - m, M);
    var margin = leftBBox.margin + rightBBox.margin;

    for (var i = m; i < M - m; i++) {
      leftBBox
          .extend(node.leaf ? toBBox(node.leafChildren[i]) : node.children[i]);
      margin += leftBBox.margin;
    }

    for (var i = M - m - 1; i >= m; i--) {
      rightBBox
          .extend(node.leaf ? toBBox(node.leafChildren[i]) : node.children[i]);
      margin += rightBBox.margin;
    }

    return margin;
  }

  /// adjust bboxes along the given tree path
  _adjustParentBBoxes(RBushBox bbox, List<RBushBox> path, int level) {
    for (var i = level; i >= 0; i--) {
      path[i].extend(bbox);
    }
  }

  // go through the path, removing empty nodes and updating bboxes
  _condense(List<_RBushNode<T>> path) {
    for (var i = path.length - 1; i >= 0; i--) {
      if (path[i].childrenLength == 0) {
        if (i > 0) {
          if (path[i - 1].leaf) {
            path[i - 1].leafChildren.remove(path[i]);
          } else {
            path[i - 1].children.remove(path[i]);
          }
        } else {
          clear();
        }
      } else {
        _calcBBox(path[i]);
      }
    }
  }

  _calcBBox(_RBushNode<T> node) {
    _distBBox(node, 0,
        node.leaf ? node.leafChildren.length : node.children.length, node);
  }

  _RBushNode _distBBox(_RBushNode<T> node, int k, int p,
      [_RBushNode? destNode]) {
    destNode ??= _RBushNode([]);
    destNode.minX = double.infinity;
    destNode.minY = double.infinity;
    destNode.maxX = double.negativeInfinity;
    destNode.maxY = double.negativeInfinity;

    for (int i = k; i < p; i++) {
      if (node.leaf) {
        destNode.extend(toBBox(node.leafChildren[i]));
      } else {
        destNode.extend(node.children[i]);
      }
    }
    return destNode;
  }

  _multiSelect(List<T> arr, int left, int right, int n, MinXYGetter<T> getter) {
    final stack = [left, right];
    final compare = (T a, T b) => getter(a).compareTo(getter(b));
    while (stack.isNotEmpty) {
      right = stack.removeLast();
      left = stack.removeLast();
      if (right - left <= n) continue;
      final mid = left + ((right - left).toDouble() / n / 2).ceil() * n;
      quickSelect(arr, mid, left, right, compare);
      stack.addAll([left, mid, mid, right]);
    }
  }
}

/// Bounding box for an r-tree item.
///
/// If your item class extends this one, writing `toBBox` function
/// would be easier. Also it's got some useful methods like [contains]
/// and [area].
class RBushBox {
  double minX;
  double minY;
  double maxX;
  double maxY;

  RBushBox({
    this.minX = double.infinity,
    this.minY = double.infinity,
    this.maxX = double.negativeInfinity,
    this.maxY = double.negativeInfinity,
  });

  RBushBox.fromList(List<dynamic> bbox)
      : minX = bbox[0].toDouble(),
        minY = bbox[1].toDouble(),
        maxX = bbox[2].toDouble(),
        maxY = bbox[3].toDouble();

  /// Extends this box's bounds to cover [b].
  extend(RBushBox b) {
    minX = min(minX, b.minX);
    minY = min(minY, b.minY);
    maxX = max(maxX, b.maxX);
    maxY = max(maxY, b.maxY);
  }

  /// Calculates area: `dx * dy`.
  double get area => (maxX - minX) * (maxY - minY);

  /// Calculates the box's half-perimeter: `dx + dy`.
  double get margin => (maxX - minX) + (maxY - minY);

  /// Calculates area for an extendes bounding box that
  /// would cover both this one and [b]. See [extend] for
  /// the extension method.
  double enlargedArea(RBushBox b) {
    return (max(b.maxX, maxX) - min(b.minX, minX)) *
        (max(b.maxY, maxY) - min(b.minY, minY));
  }

  /// Calculates area for an intersection box of this
  /// and [b].
  double intersectionArea(RBushBox b) {
    final minX = max(this.minX, b.minX);
    final minY = max(this.minY, b.minY);
    final maxX = min(this.maxX, b.maxX);
    final maxY = min(this.maxY, b.maxY);
    return max(0, maxX - minX) * max(0, maxY - minY);
  }

  bool contains(RBushBox b) {
    return minX <= b.minX && minY <= b.minY && b.maxX <= maxX && b.maxY <= maxY;
  }

  bool intersects(RBushBox b) {
    return b.minX <= maxX && b.minY <= maxY && b.maxX >= minX && b.maxY >= minY;
  }

  /// Calculates squared distance from ([x], [y]) to this box.
  double distanceSq(double x, double y) {
    final dx = _axisDist(x, minX, maxX);
    final dy = _axisDist(y, minY, maxY);
    return dx * dx + dy * dy;
  }

  double _axisDist(double k, double min, double max) {
    return k < min
        ? min - k
        : k <= max
            ? 0
            : k - max;
  }

  @override
  bool operator ==(Object other) {
    if (other is! RBushBox) return false;
    return minX == other.minX &&
        minY == other.minY &&
        maxX == other.maxX &&
        maxY == other.maxY;
  }

  @override
  int get hashCode =>
      minX.hashCode + maxX.hashCode + minY.hashCode + maxY.hashCode;

  @override
  String toString() => '{$minX, $minY, $maxX, $maxY}';
}

/// Internal class for nodes inside the r-tree.
class _RBushNode<T> extends RBushBox {
  final List<_RBushNode<T>> children;
  final List<T> leafChildren;
  int height = 1;
  bool leaf;

  _RBushNode(this.children, [List<T>? leafChildren])
      : leaf = children.isEmpty,
        leafChildren = leafChildren ?? [];

  int get childrenLength => leaf ? leafChildren.length : children.length;

  bool _listsEqual(List<dynamic> a, List<dynamic> b) {
    if (a == b) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (other is! _RBushNode) return false;
    return height == other.height &&
        leaf == other.leaf &&
        _listsEqual(children, other.children) &&
        _listsEqual(leafChildren, other.leafChildren);
  }
}

/// Internal class for a queue elements for the `RBushBase.knn` method.
class _KnnElement<T> implements Comparable<_KnnElement> {
  _RBushNode<T>? node;
  T? item;
  double dist;

  _KnnElement({this.node, this.item, required this.dist}) {
    if (node == null && item == null) {
      throw ArgumentError('Either node or item should be not null');
    }
  }

  @override
  int compareTo(other) => dist.compareTo(other.dist);
}

/// An r-tree for [RBushElement]: a convenience class
/// that does not make you write accessor functions.
class RBush<T> extends RBushBase<RBushElement<T>> {
  RBush([int maxEntries = 9])
      : super(
          maxEntries: maxEntries,
          toBBox: (item) => item,
          getMinX: (item) => item.minX,
          getMinY: (item) => item.minY,
        );
}

/// A convenient r-tree for working directly with data objects, uncoupling
/// these from bounding boxes. Encapsulates [RBush], so for bulk inserts
/// this class still needs a list of [RBushElement]s.
class RBushDirect<T> {
  final RBush<T> _tree;
  final Map<T, RBushElement<T>> _boxes = {};

  RBushDirect([int maxEntries = 9]) : _tree = RBush<T>(maxEntries);

  List<T> all() => _tree.all().map((e) => e.data).toList();
  List<T> search(RBushBox bbox) =>
      _tree.search(bbox).map((e) => e.data).toList();
  bool collides(RBushBox bbox) => _tree.collides(bbox);
  clear() => _tree.clear();
  remove(T? item) => _tree.remove(_boxes[item]);

  List<T> knn(double x, double y, int k,
          {bool Function(T item)? predicate, double? maxDistance}) =>
      _tree
          .knn(x, y, k,
              predicate: (e) => predicate == null || predicate(e.data),
              maxDistance: maxDistance)
          .map((e) => e.data)
          .toList();

  RBushDirect<T> load(Iterable<RBushElement<T>> items) {
    if (items.any((item) => _boxes.containsKey(item))) {
      throw StateError(
          'Cannot have duplicates in the tree, use RBush class for that.');
    }
    _tree.load(items);
    _boxes.addAll({for (final i in items) i.data: i});
    return this;
  }

  insert(RBushBox bbox, T item) {
    if (_boxes.containsKey(item)) {
      throw StateError(
          'Cannot have duplicate $item in the tree, use RBush class for that.');
    }
    final element = RBushElement(
        minX: bbox.minX,
        minY: bbox.minY,
        maxX: bbox.maxX,
        maxY: bbox.maxY,
        data: item);
    _tree.insert(element);
    _boxes[item] = element;
  }
}

/// A container for your data, to be used with [RBush].
class RBushElement<T> extends RBushBox {
  final T data;

  RBushElement({
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
    required this.data,
  }) : super(minX: minX, maxX: maxX, minY: minY, maxY: maxY);

  RBushElement.fromList(List<dynamic> bbox, this.data) : super.fromList(bbox);
}
