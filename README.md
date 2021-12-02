# RBush

RBush is a high-performance Dart library for 2D **spatial indexing** of points and rectangles.
It's based on an optimized **R-tree** data structure with **bulk insertion** support.

*Spatial index* is a special data structure for points and rectangles
that allows you to perform queries like "all items within this bounding box" very efficiently
(e.g. hundreds of times faster than looping over all items).
It's most commonly used in maps and data visualizations.

## Usage

```dart
// Create a tree with up to 16 elements in a leaf.
final tree = RBush(16);

// Bulk load elements (empty in this case, so here it's a no-op).
tree.load(<RBushElement>[]);

// Insert a single element.
tree.insert(RBushElement(
  minX: 10, minY: 10,
  maxX: 20, maxY: 30,
  data: 'sample data'
));

// Find the element we've inserted.
final List<RBushElement> found = tree.search(
    RBushBox(minX: 5, minY: 5, maxX: 25, maxY: 25));

// Remove all elements from the tree.
tree.clear();
```

An optional argument to `RBush` defines the maximum number of entries in a tree node.
`9` (used by default) is a reasonable choice for most applications.
Higher value means faster insertion and slower search, and vice versa.

To store items of a different type, extend from (or instantiate) `RBushBase<T>`.
For example:

```dart
class MyItem {
  final String id;
  final LatLng location;
  
  const MyItem(this.id, this.location);
}

final tree = RBushBase<MyItem>(
  maxEntries: 4,
  toBBox: (item) => RBushBox(
    minX: item.location.longitude,
    maxX: item.location.longitude,
    minY: item.location.latitude,
    maxY: item.location.latitude,
  ),
  getMinX: (item) => item.location.longitude,
  getMinY: (item) => item.location.latitude,
);
```

### K Nearest Neighbours

The `RBushBase` class also includes a `knn()` method for the nearest neighbours
search. This is especially useful when using the r-tree to store point features,
like in the example above.

Note that for larger geographical areas the distance would be wrong, since the
class uses pythagorean distances (`dx² + dy²`), not Haversine or great circle.

## Tiny Queue and Quick Select

This package also includes ported fast versions of a priority queue and
a selection algorithm. These are used internally by the r-tree, but might
be useful for you as well.

## Upstream

This library is a straight-up port of several JavaScript libraries written
by Vladimir Agafonkin:

* [RBush 3.0.1](https://github.com/mourner/rbush)
* [RBush-knn 3.0.1](https://github.com/mourner/rbush-knn)
* [QuickSelect 2.0.0](https://github.com/mourner/quickselect)
* [TinyQueue 2.0.3](https://github.com/mourner/tinyqueue)

All of these are published under MIT or ISC licenses.