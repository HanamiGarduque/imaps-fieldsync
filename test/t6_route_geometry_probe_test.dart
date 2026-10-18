// T6 ROUTE-GEOMETRY PROBE — throwaway analysis harness for the geometry-review
// gate. No production code is touched. It measures the official artwork's real
// free space (ribbon fills + pin eye as obstacles, the wordmark as a soft
// obstacle), checks the official kit route's clearance, counts the current
// search line's ridge crossings, computes a channel-locked replacement search
// route (A* over the medial space, then the widget's own Catmull-Rom
// construction) and validates it with exact edge distances. Writes report.txt
// and annotated diagrams under T6-geometry/diagrams.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_cinematic_intro.dart';
import 'package:imaps_fieldsync/core/widgets/fieldsync_logo_geometry.dart';

// Analysis window: the lockup's own viewBox x-range, extended 86 units below
// the viewBox floor so the entry approach from (596,1260) stays inside.
const double aX0 = 212.0;
const double aY0 = 69.0;
const int aW = 887; // x: 212..1099
const int aH = 1201; // y: 69..1270

const String kOutDir =
    r'C:\Users\Ralph Lauren\AppData\Local\Temp\opencode\splash-cinematic-20261017\T6-geometry\diagrams';

// Margin ladder for the A* attempts, in viewBox units. 6.5 = half the route
// stroke (5 / 2) + the glow allowance (~3.3) + slack (~0.7).
const List<double> kMargins = [6.5, 5.5, 4.5, 3.5, 3.0, 2.5];

const List<Offset> kCurrentWaypoints = [
  Offset(629.500, 974.500), Offset(649.885, 956.115), Offset(672.027, 941.973),
  Offset(694.755, 929.245), Offset(715.018, 911.982), Offset(720.500, 886.252),
  Offset(735.110, 864.890), Offset(754.374, 846.626), Offset(772.051, 825.949),
  Offset(785.500, 803.519), Offset(794.500, 779.833), Offset(797.500, 753.076),
  Offset(795.500, 728.147), Offset(786.058, 706.058), Offset(764.916, 689.500),
  Offset(743.644, 681.500), Offset(719.544, 679.500), Offset(692.786, 682.500),
  Offset(670.514, 691.500), Offset(650.500, 708.858), Offset(637.054, 728.946),
  Offset(633.500, 752.988), Offset(636.500, 779.746), Offset(645.500, 802.603),
  Offset(654.766, 826.766), Offset(656.500, 854.047), Offset(644.500, 871.319),
  Offset(623.728, 882.272), Offset(600.379, 893.500), Offset(576.107, 902.500),
  Offset(552.249, 912.500), Offset(529.302, 924.698), Offset(509.090, 943.500),
  Offset(486.889, 957.500), Offset(466.097, 974.903), Offset(439.855, 977.855),
  Offset(414.901, 970.500), Offset(406.287, 952.713), Offset(421.500, 931.014),
  Offset(435.500, 912.328), Offset(451.178, 890.822), Offset(470.489, 877.500),
  Offset(493.220, 864.780), Offset(516.534, 853.466), Offset(533.500, 834.837),
  Offset(553.500, 820.394), Offset(558.500, 794.465), Offset(558.576, 770.576),
  Offset(558.500, 745.920), Offset(560.500, 719.577), Offset(567.500, 694.477),
  Offset(572.413, 669.413), Offset(557.518, 650.500), Offset(536.418, 639.500),
  Offset(512.835, 650.165), Offset(501.643, 670.357), Offset(490.500, 693.741),
  Offset(487.965, 719.035), Offset(478.500, 743.114), Offset(471.702, 768.298),
  Offset(460.509, 790.491), Offset(444.610, 804.390), Offset(423.455, 819.500),
  Offset(399.861, 830.139), Offset(380.500, 847.190), Offset(356.538, 856.500),
  Offset(329.113, 855.113), Offset(318.506, 831.506), Offset(322.272, 806.728),
  Offset(332.879, 783.121), Offset(354.728, 768.272), Offset(374.406, 749.594),
  Offset(387.500, 727.018),
];

/// The line shipped in HEAD (rejected 2026-10-17: 14 ridge-fill entries,
/// deepest 28.6u). Kept only as the "before" geometry for the comparison
/// diagram, never drawn by the widget.
const List<Offset> kPreviousWaypoints = [
  Offset(596, 1260),
  Offset(736, 1076),
  Offset(606, 946),
  Offset(806, 872),
  Offset(614, 762),
  Offset(764, 628),
  Offset(588, 682),
  Offset(368, 900),
];

// User-approved direction, translated from the annotated corridor diagram.
const List<Offset> kGreenTrace = [
  Offset(629, 974), Offset(702, 920), Offset(758, 856),
  Offset(783, 789), Offset(789, 739), Offset(788, 719),
  Offset(756, 693), Offset(721, 689), Offset(682, 693),
  Offset(652, 716), Offset(641, 752), Offset(642, 786),
  Offset(656, 839), Offset(659, 862), Offset(648, 878),
  Offset(581, 906), Offset(505, 943), Offset(432, 970),
  Offset(409, 970), Offset(403, 953), Offset(419, 919),
  Offset(455, 882), Offset(502, 866), Offset(531, 830),
  Offset(558, 796), Offset(563, 775), Offset(562, 750),
  Offset(561, 725), Offset(571, 668), Offset(563, 656),
  Offset(548, 642), Offset(526, 645), Offset(509, 670),
  Offset(492, 722), Offset(469, 783), Offset(453, 805),
  Offset(428, 823), Offset(381, 848), Offset(345, 856),
  Offset(326, 852), Offset(322, 835), Offset(326, 802),
  Offset(358.7, 765.4),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('T6Evidence')..addFont(Future.value(ByteData.sublistView(
      File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytesSync(),
    )))).load();
  });

  testWidgets('T6 route geometry probe', (tester) async {
    final result = await tester.runAsync<double>(_runAnalysis);
    final parityMax = result ?? double.nan;
    expect(parityMax.isNaN || parityMax < 0.5, isTrue,
        reason: 'the local waypoint copy must replicate the widget search '
            'path; max deviation was $parityMax');
  }, timeout: const Timeout(Duration(minutes: 12)));
}

// ---------------------------------------------------------------------------
// Raster masks + chamfer distance fields (1 px = 1 viewBox unit)
// ---------------------------------------------------------------------------

class _Masks {
  _Masks(this.obstacles, this.obsUnion, this.letters, this.dObs, this.dLet);
  final List<Uint8List> obstacles; // 9 ribbon fills + the pin eye disk
  final Uint8List obsUnion;
  final Uint8List letters; // wordmark fills
  final Float32List dObs; // distance to the nearest obstacle pixel
  final Float32List dLet;

  bool _in(Offset p) {
    final x = p.dx - aX0;
    final y = p.dy - aY0;
    return x >= 0 && y >= 0 && x < aW && y < aH;
  }

  int _i(Offset p) => (p.dy - aY0).floor() * aW + (p.dx - aX0).floor();
  bool obstacleAt(Offset p) => _in(p) && obsUnion[_i(p)] != 0;
  bool letterAt(Offset p) => _in(p) && letters[_i(p)] != 0;
  double dObsAt(Offset p) => _in(p) ? dObs[_i(p)] : 1e6;
  double dLetAt(Offset p) => _in(p) ? dLet[_i(p)] : 1e6;
}

Future<Uint8List> _rasterize(void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()));
  canvas.translate(-aX0, -aY0);
  draw(canvas);
  final img = await rec.endRecording().toImage(aW, aH);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  final px = bd!.buffer.asUint8List();
  final out = Uint8List(aW * aH);
  for (var i = 0; i < out.length; i++) {
    out[i] = px[i * 4 + 3] >= 128 ? 1 : 0;
  }
  return out;
}

Float32List _chamfer(Uint8List seed) {
  const diag = 1.41421356;
  final n = aW * aH;
  final d = Float32List(n);
  for (var i = 0; i < n; i++) {
    d[i] = seed[i] != 0 ? 0.0 : 1e9;
  }
  for (var y = 0; y < aH; y++) {
    final row = y * aW;
    for (var x = 0; x < aW; x++) {
      final i = row + x;
      var v = d[i];
      if (x > 0 && d[i - 1] + 1.0 < v) v = d[i - 1] + 1.0;
      if (y > 0) {
        if (d[i - aW] + 1.0 < v) v = d[i - aW] + 1.0;
        if (x > 0 && d[i - aW - 1] + diag < v) v = d[i - aW - 1] + diag;
        if (x < aW - 1 && d[i - aW + 1] + diag < v) v = d[i - aW + 1] + diag;
      }
      d[i] = v;
    }
  }
  for (var y = aH - 1; y >= 0; y--) {
    final row = y * aW;
    for (var x = aW - 1; x >= 0; x--) {
      final i = row + x;
      var v = d[i];
      if (x < aW - 1 && d[i + 1] + 1.0 < v) v = d[i + 1] + 1.0;
      if (y < aH - 1) {
        if (d[i + aW] + 1.0 < v) v = d[i + aW] + 1.0;
        if (x < aW - 1 && d[i + aW + 1] + diag < v) v = d[i + aW + 1] + diag;
        if (x > 0 && d[i + aW - 1] + diag < v) v = d[i + aW - 1] + diag;
      }
      d[i] = v;
    }
  }
  return d;
}

Future<_Masks> _buildMasks() async {
  final white = Paint()..color = const Color(0xFFFFFFFF);
  final obstacles = <Uint8List>[];
  for (final path in FieldSyncLogoGeometry.fingerprints) {
    obstacles.add(await _rasterize((c) => c.drawPath(path, white)));
  }
  obstacles.add(await _rasterize((c) => c.drawCircle(
        const Offset(FieldSyncLogoGeometry.pinEyeX,
            FieldSyncLogoGeometry.pinEyeY),
        FieldSyncLogoGeometry.pinEyeR,
        white,
      )));
  final letters = await _rasterize((c) {
    for (final p in FieldSyncLogoGeometry.wordmark) {
      c.drawPath(p, white);
    }
  });
  final union = Uint8List(aW * aH);
  for (final m in obstacles) {
    for (var i = 0; i < union.length; i++) {
      if (m[i] != 0) union[i] = 1;
    }
  }
  return _Masks(obstacles, union, letters, _chamfer(union), _chamfer(letters));
}

// ---------------------------------------------------------------------------
// Exact edge sampling index (distances for validation/reporting)
// ---------------------------------------------------------------------------

class _EdgeIndex {
  final List<Offset> pts = [];
  final List<int> ids = [];
  final Map<int, List<int>> _cells = {};
  static const double _cell = 16.0;
  int _key(int cx, int cy) => cx * 10007 + cy;

  void _add(Offset p, int id) {
    final i = pts.length;
    pts.add(p);
    ids.add(id);
    _cells
        .putIfAbsent(_key((p.dx / _cell).floor(), (p.dy / _cell).floor()),
            () => <int>[])
        .add(i);
  }

  void addPath(Path path, int id, double step) {
    for (final m in path.computeMetrics()) {
      if (m.length <= 0) continue;
      var d = 0.0;
      while (d < m.length) {
        _add(m.getTangentForOffset(d)!.position, id);
        d += step;
      }
      _add(m.getTangentForOffset(m.length)!.position, id);
    }
  }

  void addRing(Offset center, double radius, int id, double step) {
    final count = (2 * math.pi * radius / step).ceil();
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count;
      _add(Offset(center.dx + radius * math.cos(a),
          center.dy + radius * math.sin(a)), id);
    }
  }

  /// Best distance per id found within [maxR] units of [p].
  Map<int, double> perId(Offset p, double maxR) {
    final out = <int, double>{};
    final rc = (maxR / _cell).ceil();
    final cx = (p.dx / _cell).floor();
    final cy = (p.dy / _cell).floor();
    for (var gx = cx - rc; gx <= cx + rc; gx++) {
      for (var gy = cy - rc; gy <= cy + rc; gy++) {
        final list = _cells[_key(gx, gy)];
        if (list == null) continue;
        for (final i in list) {
          final dd = (pts[i] - p).distance;
          if (dd > maxR) continue;
          final id = ids[i];
          final cur = out[id];
          if (cur == null || dd < cur) out[id] = dd;
        }
      }
    }
    return out;
  }

  double minDist(Offset p, double maxR) {
    var best = double.infinity;
    for (final v in perId(p, maxR).values) {
      if (v < best) best = v;
    }
    return best;
  }
}

List<Offset> _sample(Path path, double step) {
  final out = <Offset>[];
  for (final m in path.computeMetrics()) {
    if (m.length <= 0) continue;
    var d = 0.0;
    while (d < m.length) {
      out.add(m.getTangentForOffset(d)!.position);
      d += step;
    }
    out.add(m.getTangentForOffset(m.length)!.position);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Widget-parity search-path construction (same maths as _prepare())
// ---------------------------------------------------------------------------

class _SearchBuild {
  _SearchBuild(this.legs, this.full, this.join, this.joinDir);
  final List<Path> legs;
  final Path full;
  final Offset join;
  final Offset joinDir;
}

_SearchBuild _buildSearch(List<Offset> waypoints) {
  final routeMetric = FieldSyncLogoGeometry.route.computeMetrics().first;
  final join = routeMetric.getTangentForOffset(0)!.position;
  final ahead = routeMetric.getTangentForOffset(0.5)!.position;
  final joinDir = (ahead - join) / (ahead - join).distance;
  final points = <Offset>[...waypoints, join];
  final legs = <Path>[];
  final full = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final from = points[i];
    final to = points[i + 1];
    final previous = i == 0 ? points[0] : points[i - 1];
    final next = i + 2 < points.length ? points[i + 2] : null;
    final c1 = from + (to - previous) / 6;
    final c2 = next != null
        ? to - (next - from) / 6
        : to - joinDir * ((to - from).distance / 6);
    legs.add(Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy));
    full.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
  }
  return _SearchBuild(legs, full, join, joinDir);
}

// ---------------------------------------------------------------------------
// Clearance checking
// ---------------------------------------------------------------------------

class _PathCheck {
  double minClear = double.infinity;
  Offset minAt = Offset.zero;
  int minId = -1;
  int entries = 0;
  final List<Offset> entryPoints = [];
  double deepest = 0;
  Offset deepestAt = Offset.zero;
  double minLetter = double.infinity;
  Offset minLetterAt = Offset.zero;
  double minBalance = double.infinity;
  Offset minBalanceAt = Offset.zero;
}

_PathCheck _checkPath(
    List<Offset> samples, _EdgeIndex obs, _EdgeIndex letters, _Masks masks) {
  final c = _PathCheck();
  var prevInside = false;
  for (final p in samples) {
    final per = obs.perId(p, 80);
    var d1 = double.infinity;
    var id1 = -1;
    var d2 = double.infinity;
    per.forEach((id, d) {
      if (d < d1) {
        d2 = d1;
        d1 = d;
        id1 = id;
      } else if (d < d2) {
        d2 = d;
      }
    });
    if (d1 < c.minClear) {
      c.minClear = d1;
      c.minAt = p;
      c.minId = id1;
    }
    final inside = masks.obstacleAt(p);
    if (inside && d1 > c.deepest) {
      c.deepest = d1;
      c.deepestAt = p;
    }
    if (inside && !prevInside) {
      c.entries++;
      if (c.entryPoints.length < 40) c.entryPoints.add(p);
    }
    prevInside = inside;
    final dl = letters.minDist(p, 80);
    if (dl < c.minLetter) {
      c.minLetter = dl;
      c.minLetterAt = p;
    }
    if (d1.isFinite && d2.isFinite && d2 > 0.5) {
      final b = d1 / d2;
      if (b < c.minBalance) {
        c.minBalance = b;
        c.minBalanceAt = p;
      }
    }
  }
  return c;
}

double _pointSegDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.distanceSquared;
  if (l2 == 0) return (p - a).distance;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2;
  t = t.clamp(0.0, 1.0).toDouble();
  return (p - (a + ab * t)).distance;
}

List<Offset> _rdp(List<Offset> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <List<int>>[
    [0, pts.length - 1]
  ];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final a = range[0];
    final b = range[1];
    var maxD = -1.0;
    var maxI = -1;
    for (var i = a + 1; i < b; i++) {
      final d = _pointSegDist(pts[i], pts[a], pts[b]);
      if (d > maxD) {
        maxD = d;
        maxI = i;
      }
    }
    if (maxD > eps && maxI > 0) {
      keep[maxI] = true;
      stack.add([a, maxI]);
      stack.add([maxI, b]);
    }
  }
  final out = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    if (keep[i]) out.add(pts[i]);
  }
  return out;
}

List<Offset> _resamplePolyline(List<Offset> pts, double spacing) {
  if (pts.length < 2) return List.of(pts);
  final out = <Offset>[pts.first];
  var want = spacing;
  for (var i = 0; i < pts.length - 1; i++) {
    var a = pts[i];
    final b = pts[i + 1];
    while (true) {
      final len = (b - a).distance;
      if (len < 1e-9) break;
      if (len >= want) {
        final np = a + (b - a) * (want / len);
        out.add(np);
        a = np;
        want = spacing;
      } else {
        want -= len;
        break;
      }
    }
  }
  if ((out.last - pts.last).distance > spacing * 0.4) out.add(pts.last);
  return out;
}

// ---------------------------------------------------------------------------
// Grids: free space, connectivity, A*
// ---------------------------------------------------------------------------

int _gid(int x, int y) => y * aW + x;
int _gx(int id) => id % aW;
int _gy(int id) => id ~/ aW;

Uint8List _freeGrid(_Masks masks, double margin) {
  final n = aW * aH;
  final free = Uint8List(n);
  final thr = margin + 1.0; // chamfer slack over the requested margin
  for (var i = 0; i < n; i++) {
    if (masks.obsUnion[i] != 0 || masks.letters[i] != 0) continue;
    if (masks.dObs[i] < thr || masks.dLet[i] < thr) continue;
    free[i] = 1;
  }
  return free;
}

int _nearestFree(Uint8List free, int x, int y) {
  if (x >= 0 && y >= 0 && x < aW && y < aH && free[_gid(x, y)] != 0) {
    return _gid(x, y);
  }
  for (var r = 1; r <= 80; r++) {
    for (var dx = -r; dx <= r; dx++) {
      for (var dy = -r; dy <= r; dy++) {
        if (dx.abs() != r && dy.abs() != r) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= aW || ny >= aH) continue;
        if (free[_gid(nx, ny)] != 0) return _gid(nx, ny);
      }
    }
  }
  return -1;
}

bool _connected(Uint8List free, int fromId, int toId) {
  final seen = Uint8List(aW * aH);
  final queue = <int>[fromId];
  seen[fromId] = 1;
  var head = 0;
  while (head < queue.length) {
    final cur = queue[head++];
    if (cur == toId) return true;
    final x = _gx(cur);
    final y = _gy(cur);
    if (x > 0) {
      final n = cur - 1;
      if (free[n] != 0 && seen[n] == 0) {
        seen[n] = 1;
        queue.add(n);
      }
    }
    if (x < aW - 1) {
      final n = cur + 1;
      if (free[n] != 0 && seen[n] == 0) {
        seen[n] = 1;
        queue.add(n);
      }
    }
    if (y > 0) {
      final n = cur - aW;
      if (free[n] != 0 && seen[n] == 0) {
        seen[n] = 1;
        queue.add(n);
      }
    }
    if (y < aH - 1) {
      final n = cur + aW;
      if (free[n] != 0 && seen[n] == 0) {
        seen[n] = 1;
        queue.add(n);
      }
    }
  }
  return false;
}

class _MinHeap {
  final List<double> keys = [];
  final List<int> values = [];
  int get size => keys.length;

  void push(double k, int v) {
    keys.add(k);
    values.add(v);
    var i = keys.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (keys[parent] <= keys[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = values[0];
    final lastK = keys.removeLast();
    final lastV = values.removeLast();
    if (keys.isNotEmpty) {
      keys[0] = lastK;
      values[0] = lastV;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = 2 * i + 2;
        var m = i;
        if (l < keys.length && keys[l] < keys[m]) m = l;
        if (r < keys.length && keys[r] < keys[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = keys[a];
    keys[a] = keys[b];
    keys[b] = k;
    final v = values[a];
    values[a] = values[b];
    values[b] = v;
  }
}

List<Offset>? _astar(Uint8List free, Float32List dObs, int sx, int sy, int tx,
    int ty, double margin) {
  final n = aW * aH;
  final g = Float32List(n);
  g.fillRange(0, n, double.infinity);
  final parent = Int32List(n);
  parent.fillRange(0, n, -1);
  final closed = Uint8List(n);
  final heap = _MinHeap();
  final startId = _gid(sx, sy);
  final targetId = _gid(tx, ty);

  double h(int x, int y) {
    final dx = (x - tx).abs().toDouble();
    final dy = (y - ty).abs().toDouble();
    return (dx + dy) + (1.41421356 - 2.0) * math.min(dx, dy);
  }

  g[startId] = 0;
  heap.push(h(sx, sy), startId);
  const dxs = [1, -1, 0, 0, 1, 1, -1, -1];
  const dys = [0, 0, 1, -1, 1, -1, 1, -1];
  const isDiag = [false, false, false, false, true, true, true, true];
  while (heap.size > 0) {
    final cur = heap.pop();
    if (closed[cur] != 0) continue;
    closed[cur] = 1;
    if (cur == targetId) {
      final rev = <int>[];
      var node = cur;
      while (node != -1) {
        rev.add(node);
        node = parent[node];
      }
      final out = <Offset>[];
      for (var i = rev.length - 1; i >= 0; i--) {
        out.add(Offset(aX0 + _gx(rev[i]) + 0.5, aY0 + _gy(rev[i]) + 0.5));
      }
      return out;
    }
    final cx = _gx(cur);
    final cy = _gy(cur);
    final cg = g[cur];
    for (var k = 0; k < 8; k++) {
      final nx = cx + dxs[k];
      final ny = cy + dys[k];
      if (nx < 0 || ny < 0 || nx >= aW || ny >= aH) continue;
      final nid = _gid(nx, ny);
      if (free[nid] == 0) continue;
      if (isDiag[k] &&
          (free[_gid(cx + dxs[k], cy)] == 0 ||
              free[_gid(cx, cy + dys[k])] == 0)) {
        continue;
      }
      final step = isDiag[k] ? 1.41421356 : 1.0;
      final d = dObs[nid];
      final mult = _channelCost
          ? 1.0 +
              (d < 8 ? (8 - d) * 0.25 : 0.0) +
              (d > 18 ? math.min((d - 18) / 30, 1.0) * 2.0 : 0.0)
          : 1.0 + 80.0 / (math.max(d - margin, 0.0) + 2.0);
      final ng = cg + step * mult;
      if (ng < g[nid]) {
        g[nid] = ng;
        parent[nid] = cur;
        heap.push(ng + h(nx, ny), nid);
      }
    }
  }
  return null;
}

const List<String> kObstacleNames = [
  'fp-1', 'fp-2', 'fp-3', 'fp-4', 'fp-5',
  'fp-9', 'fp-13', 'fp-14', 'fp-15', 'pin-eye',
];

String _obsName(int id) =>
    id >= 0 && id < kObstacleNames.length ? kObstacleNames[id] : 'none(>80u)';

/// When true, [_astar] prefers riding ridge channels (band ~8-18u from the
/// nearest fill) instead of the default open-space preference.
bool _channelCost = false;

/// Maintenance helper for [_refineWaypoints]: rebuild the search legs, sample
/// them densely, and measure with the exact edge index.
_PathCheck __evaluate(
    List<Offset> wps, _EdgeIndex obs, _EdgeIndex letters, _Masks masks) {
  final b = _buildSearch(wps);
  final samples = <Offset>[];
  for (final leg in b.legs) {
    samples.addAll(_sample(leg, 0.3));
  }
  return _checkPath(samples, obs, letters, masks);
}

({
  List<Offset> wps,
  _PathCheck check,
}) _refineWaypoints(List<Offset> wps0, List<Offset> raw, double target,
    _EdgeIndex obs, _EdgeIndex letters, _Masks masks) {
  var wps = List<Offset>.of(wps0);
  var bestWps = List<Offset>.of(wps);
  _PathCheck? best;
  for (var round = 0; round < 26; round++) {
    final c = __evaluate(wps, obs, letters, masks);
    if (best == null || c.minClear > best.minClear) {
      best = c;
      bestWps = List<Offset>.of(wps);
    }
    if (c.minClear >= target - 0.05 || wps.length >= 24) break;
    // Insert, as a new waypoint, the raw A* point nearest the worst sample.
    final worst = c.minAt;
    var bi = -1;
    var bd = double.infinity;
    for (var i = 0; i < raw.length; i++) {
      final d = (raw[i] - worst).distance;
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    if (bi < 0) break;
    var q = raw[bi];
    var minWp = double.infinity;
    for (final wp in wps) {
      final d = (wp - q).distance;
      if (d < minWp) minWp = d;
    }
    if (minWp < 3) q = (q + worst) / 2;
    final join = _buildSearch(wps).join;
    final fullPts = <Offset>[...wps, join];
    var slot = wps.length;
    var midBest = double.infinity;
    for (var k = 0; k < fullPts.length - 1; k++) {
      final mid = (fullPts[k] + fullPts[k + 1]) / 2;
      final d = (mid - q).distance;
      if (d < midBest) {
        midBest = d;
        slot = k + 1;
      }
    }
    if (slot > wps.length) slot = wps.length;
    wps.insert(slot, q);
  }
  return (wps: bestWps, check: best!);
}

List<String> _describeRuns(List<Offset> samples, _EdgeIndex obs) {
  final out = <String>[];
  final ids = <int>[];
  final d1s = <double>[];
  for (final p in samples) {
    final per = obs.perId(p, 80);
    var d1 = double.infinity;
    var id1 = -1;
    per.forEach((id, d) {
      if (d < d1) {
        d1 = d;
        id1 = id;
      }
    });
    ids.add(id1);
    d1s.add(d1);
  }
  var start = 0;
  for (var i = 1; i <= samples.length; i++) {
    final closed = i == samples.length || ids[i] != ids[start];
    if (!closed) continue;
    final seg = i - start;
    if (seg >= 120 && ids[start] >= 0) {
      var mn = double.infinity;
      var mx = 0.0;
      for (var k = start; k < i; k++) {
        final v = d1s[k];
        if (v.isFinite) {
          if (v < mn) mn = v;
          if (v > mx) mx = v;
        }
      }
      out.add(
          'rides beside ${kObstacleNames[ids[start]]} for ~${(seg * 0.25).toStringAsFixed(0)}u '
          '(clearance ${mn.toStringAsFixed(1)}..${mx.toStringAsFixed(1)})');
    }
    start = i;
  }
  return out;
}

/// The intro test's own turn metric, replicated: sign changes of the heading
/// between 240 arc-length samples (deltas above 0.02 rad count). The final
/// sample uses the clamped end (v == 0 -> angle 0), exactly like the test.
int _turnCount(Path path, {int samples = 240}) {
  final metric = path.computeMetrics().first;
  if (metric.length <= 0) return 0;
  Offset pos(double d) => metric
      .getTangentForOffset(d.clamp(0.0, metric.length).toDouble())!
      .position;
  var signChanges = 0;
  int? previousSign;
  var previousAngle = 0.0;
  for (var i = 0; i <= samples; i++) {
    final offset = metric.length * i / samples;
    final a = pos(offset);
    final b = pos(offset + 0.5);
    final v = b - a;
    final angle = math.atan2(v.dy, v.dx);
    if (i > 0) {
      var delta = angle - previousAngle;
      while (delta > math.pi) {
        delta -= 2 * math.pi;
      }
      while (delta < -math.pi) {
        delta += 2 * math.pi;
      }
      if (delta.abs() > 0.02) {
        final sign = delta > 0 ? 1 : -1;
        if (previousSign != null && sign != previousSign) signChanges++;
        previousSign = sign;
      }
    }
    previousAngle = angle;
  }
  return signChanges;
}

/// Fraction of arc length within 30u of a ridge, and fraction inside the
/// genuine-groove mask (space pinched between two ridges).
({double near, double chan}) _routeFeel(
    Path path, _Masks masks, Uint8List? chan) {
  final samples = _sample(path, 0.5);
  if (samples.isEmpty) return (near: 0, chan: 0);
  var near = 0;
  var ch = 0;
  for (final s in samples) {
    if (masks.dObsAt(s) <= 30) near++;
    if (chan != null) {
      final xi = (s.dx - aX0).floor();
      final yi = (s.dy - aY0).floor();
      if (xi >= 0 && yi >= 0 && xi < aW && yi < aH) {
        if (chan[yi * aW + xi] != 0) ch++;
      }
    }
  }
  return (near: near / samples.length, chan: ch / samples.length);
}

/// Raw alpha raster of the analysis window (same frame as [_rasterize]).
Future<Uint8List> _rasterizeAlpha(void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()));
  canvas.translate(-aX0, -aY0);
  draw(canvas);
  final img = await rec.endRecording().toImage(aW, aH);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  final px = bd!.buffer.asUint8List();
  final out = Uint8List(aW * aH);
  for (var i = 0; i < out.length; i++) {
    out[i] = px[i * 4 + 3];
  }
  return out;
}

/// Draws [path] with the painter's real stroke settings (5u, round caps, and
/// the 1.1 blur when [blur]) and reports the closest rendered ink (alpha>=128)
/// and glow tail (alpha>=8) to any ridge fill, then refines the argmins with
/// the exact edge index.
Future<void> _reportInkGap(String name, Path path, _Masks masks,
    _EdgeIndex obs, void Function(String) w,
    {required bool blur}) async {
  final alpha = await _rasterizeAlpha((c) => c.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter =
            blur ? const MaskFilter.blur(BlurStyle.normal, 1.1) : null));
  var overlapInk = 0;
  var overlapGlow = 0;
  var minInk = double.infinity;
  Offset atInk = Offset.zero;
  var minGlow = double.infinity;
  Offset atGlow = Offset.zero;
  for (var i = 0; i < alpha.length; i++) {
    final a = alpha[i];
    if (a < 8) continue;
    if (masks.dObs[i] <= 0) {
      overlapGlow++;
      if (a >= 128) overlapInk++;
      continue;
    }
    final p = Offset(aX0 + (i % aW) + 0.5, aY0 + (i ~/ aW) + 0.5);
    final d = masks.dObs[i];
    if (d < minGlow) {
      minGlow = d;
      atGlow = p;
    }
    if (a >= 128 && d < minInk) {
      minInk = d;
      atInk = p;
    }
  }
  final String msg;
  if (overlapInk > 0 || overlapGlow > 0) {
    msg = 'INK OVERLAPS the ridge fills — $overlapInk px core ink / '
        '$overlapGlow px visible glow inside fills';
  } else {
    final ink = minInk.isFinite ? obs.minDist(atInk, 80) : double.nan;
    final glow = minGlow.isFinite ? obs.minDist(atGlow, 80) : double.nan;
    msg = 'no overlap; ink core gap ${ink.toStringAsFixed(2)}u at '
        '${atInk.dx.toStringAsFixed(0)},${atInk.dy.toStringAsFixed(0)}; '
        'glow tail gap ${glow.toStringAsFixed(2)}u at '
        '${atGlow.dx.toStringAsFixed(0)},${atGlow.dy.toStringAsFixed(0)} '
        '(chamfer argmin, refined exact)';
  }
  w('$name: $msg');
}

/// Rasterises [path] (fill, or stroked when [strokeWidth] is given) and counts
/// overlapping pixels against every ridge fill — intended kit overlaps versus
/// unwanted intersections in one number.
Future<void> _reportFillOverlap(String name, Path path, _Masks masks,
    void Function(String) w,
    {double? strokeWidth}) async {
  final paint = Paint()..color = const Color(0xFFFFFFFF);
  if (strokeWidth != null) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }
  final mask = await _rasterize((c) => c.drawPath(path, paint));
  final counts = List<int>.filled(masks.obstacles.length, 0);
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 0) continue;
    for (var k = 0; k < counts.length; k++) {
      if (masks.obstacles[k][i] != 0) counts[k]++;
    }
  }
  final parts = <String>[];
  var total = 0;
  for (var k = 0; k < counts.length; k++) {
    if (counts[k] == 0) continue;
    total += counts[k];
    parts.add('${kObstacleNames[k]} ${counts[k]}px');
  }
  w('$name: ${total == 0 ? 'no overlap' : '$total px overlap — ${parts.join(', ')}'}');
}

Future<double> _runAnalysis() async {
  final log = StringBuffer();
  void w(String s) {
    log.writeln(s);
    // ignore: avoid_print
    print(s);
  }

  final sw = Stopwatch()..start();
  Directory(kOutDir).createSync(recursive: true);
  w('T6 route-geometry probe');
  w('analysis window x $aX0..${aX0 + aW}, y $aY0..${aY0 + aH} (1px = 1 unit)');

  final masks = await _buildMasks();
  final obs = _EdgeIndex();
  for (var i = 0; i < FieldSyncLogoGeometry.fingerprints.length; i++) {
    obs.addPath(FieldSyncLogoGeometry.fingerprints[i], i, 0.5);
  }
  obs.addRing(const Offset(FieldSyncLogoGeometry.pinEyeX,
      FieldSyncLogoGeometry.pinEyeY), FieldSyncLogoGeometry.pinEyeR,
      FieldSyncLogoGeometry.fingerprints.length, 0.5);
  final letters = _EdgeIndex();
  for (final p in FieldSyncLogoGeometry.wordmark) {
    letters.addPath(p, 0, 0.75);
  }
  w('edge samples: obstacles ${obs.pts.length}, letters ${letters.pts.length}');

  if (Platform.environment['T6_GREEN_TRACE_ONLY'] == '1') {
    final green = _buildSearch(kGreenTrace);
    final check = _checkPath(_sample(green.full, 0.2), obs, letters, masks);
    w('USER GREEN raw: length ${green.full.computeMetrics().first.length}; '
        'clearance ${check.minClear} at ${check.minAt} '
        '(${_obsName(check.minId)}); entries ${check.entries}; '
        'letter clearance ${check.minLetter}');
    for (var i = 0; i < green.legs.length; i++) {
      final leg = _checkPath(_sample(green.legs[i], 0.25), obs, letters, masks);
      if (leg.minClear < 6.5 || leg.entries > 0) {
        w('  tight leg $i: ${kGreenTrace[i]} -> '
            '${i + 1 < kGreenTrace.length ? kGreenTrace[i + 1] : green.join}; '
            'min ${leg.minClear.toStringAsFixed(2)} at ${leg.minAt} '
            '${_obsName(leg.minId)}; entries ${leg.entries}');
      }
    }
    await _reportInkGap('user-green trace + glow', green.full, masks, obs, w,
        blur: true);
    await _writePng('10-user-green-trace.png', aW, aH, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()),
          Paint()..color = const Color(0xFF0B1220));
      c.translate(-aX0, -aY0);
      _drawArt(c, ribbonAlpha: 0.35, letterAlpha: 0.20,
          hole: const Color(0xFF0B1220));
      _drawSearch(c, green.full, color: Colors.white, width: 5);
      _drawRouteKit(c);
      c.translate(aX0, aY0);
      _label(c, 'USER GREEN: inner loop -> lower bends -> left channel -> dot',
          const Offset(20, 14));
      _label(c, 'raw trace: clearance ${check.minClear.toStringAsFixed(2)}u; '
          '${check.entries} ridge entries (not approved as collision-free)',
          const Offset(20, 44), size: 15);
    });
    // Keep the user's ordered corridor choices; adjust only inside a narrow
    // tube around the drawing to centre a full-width stroke in those gaps.
    final tube = await _rasterize((c) => c.drawPath(green.full, Paint()
      ..color = Colors.white ..style = PaintingStyle.stroke
      ..strokeWidth = 64 ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round));
    const margin = 8.0;
    final free = _freeGrid(masks, margin);
    for (var i = 0; i < free.length; i++) {
      if (tube[i] == 0) free[i] = 0;
    }
    final anchors = [...kGreenTrace, green.join].map((p) =>
      _nearestFree(free, (p.dx - aX0).floor(), (p.dy - aY0).floor())).toList();
    expect(anchors.every((id) => id >= 0), isTrue,
        reason: 'each drawn corridor must have a clearance-safe anchor');
    final raw = <Offset>[];
    for (var i = 1; i < anchors.length; i++) {
      final a = anchors[i - 1], b = anchors[i];
      final part = _astar(free, masks.dObs, _gx(a), _gy(a), _gx(b), _gy(b), margin);
      expect(part, isNotNull, reason: 'green corridor segment ${i - 1} must connect');
      raw.addAll(i == 1 ? part! : part!.skip(1));
    }
    List<Offset>? selected;
    _PathCheck? selectedCheck;
    for (final spacing in [36.0, 28.0, 20.0]) {
      final wps = _resamplePolyline(raw, spacing);
      if ((wps.last - green.join).distance < 1) wps.removeLast();
      final candidate = _buildSearch(wps);
      final c = _checkPath(_sample(candidate.full, 0.2), obs, letters, masks);
      w('centred green: spacing $spacing, ${wps.length} points, '
          'min ${c.minClear.toStringAsFixed(2)}u at ${c.minAt} '
          '${_obsName(c.minId)}, ${c.entries} entries, letters '
          '${c.minLetter.toStringAsFixed(2)}u');
      if (c.entries == 0 && c.minClear >= 6.5 && c.minLetter >= 6.5) {
        selected = wps;
        selectedCheck = c;
        break;
      }
    }
    File('$kOutDir/green-trace-report.txt').writeAsStringSync(log.toString());
    expect(selected, isNotNull, reason: 'the drawn route must clear the full envelope');
    final chosen = _buildSearch(selected!);
    await _reportInkGap('centred green + glow', chosen.full, masks, obs, w,
        blur: true);
    File('$kOutDir/green-waypoints.txt').writeAsStringSync(selected.map((p) =>
      'Offset(${p.dx.toStringAsFixed(3)}, ${p.dy.toStringAsFixed(3)}),').join('\n'));
    await _writePng('11-user-green-centred.png', aW, aH, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()),
          Paint()..color = const Color(0xFF0B1220));
      c.translate(-aX0, -aY0);
      _drawArt(c, ribbonAlpha: 0.35, letterAlpha: 0.20,
          hole: const Color(0xFF0B1220));
      _drawSearch(c, green.full, color: const Color(0xFF69FF26), width: 1.5);
      _drawSearch(c, chosen.full, color: const Color(0xFF38BDF8), width: 5);
      _drawRouteKit(c);
      c.translate(aX0, aY0);
      _label(c, 'USER GREEN: centred inner loop -> lower bends -> left -> dot',
          const Offset(20, 14));
      _label(c, 'blue: centred route; thin green: drawn reference; '
          'clearance ${selectedCheck!.minClear.toStringAsFixed(2)}u; 0 entries',
          const Offset(20, 44), size: 15);
    });
    File('$kOutDir/green-trace-report.txt').writeAsStringSync(log.toString());
    return 0;
  }

  // --- parity: the local waypoint copy must reproduce the widget path ---
  final built = _buildSearch(kCurrentWaypoints);
  final mine = _sample(built.full, 0.5);
  final theirs = _sample(FieldSyncCinematicScenePainter.searchPath, 0.5);
  var parityMax = 0.0;
  for (var i = 0; i < math.min(mine.length, theirs.length); i++) {
    final d = (mine[i] - theirs[i]).distance;
    if (d > parityMax) parityMax = d;
  }
  w('parity: local ${mine.length} vs widget ${theirs.length} samples, '
      'max deviation ${parityMax.toStringAsFixed(3)}');
  expect(mine.length, theirs.length, reason: 'full route sample counts must match');
  expect(parityMax, lessThan(0.000001), reason: 'validate the actual widget route');
  w('join point ${built.join}  direction '
      '(${built.joinDir.dx.toStringAsFixed(3)}, ${built.joinDir.dy.toStringAsFixed(3)})');

  // --- official kit route / arrowhead / dot ---
  final routeSamples = _sample(FieldSyncLogoGeometry.route, 0.25);
  final routeCheck = _checkPath(routeSamples, obs, letters, masks);
  w('');
  w('== OFFICIAL KIT ROUTE ==');
  w('samples ${routeSamples.length}, min clearance '
      '${routeCheck.minClear.toStringAsFixed(2)} at ${routeCheck.minAt} '
      '(nearest ${_obsName(routeCheck.minId)})');
  w('inside fills: ${routeCheck.entries} entries, deepest '
      '${routeCheck.deepest.toStringAsFixed(2)} at ${routeCheck.deepestAt}');
  w('min letter distance ${routeCheck.minLetter.toStringAsFixed(2)}');
  final ahCheck = _checkPath(
      _sample(FieldSyncLogoGeometry.routeArrowhead, 0.2), obs, letters, masks);
  w('arrowhead: min clearance ${ahCheck.minClear.toStringAsFixed(2)} at '
      '${ahCheck.minAt}, entries ${ahCheck.entries}');
  final dot =
      const Offset(FieldSyncLogoGeometry.siteDotX, FieldSyncLogoGeometry.siteDotY);
  final dotDist = obs.minDist(dot, 60);
  w('site dot centre $dot r ${FieldSyncLogoGeometry.siteDotR}: nearest edge '
      '${dotDist.toStringAsFixed(2)} -> lap '
      '${(dotDist - FieldSyncLogoGeometry.siteDotR).toStringAsFixed(2)}');

  // --- current authored search line ---
  final searchCheck = _checkPath(_sample(built.full, 0.2), obs, letters, masks);
  w('');
  w('== CURRENT AUTHORED SEARCH LINE ==');
  w('min clearance ${searchCheck.minClear.toStringAsFixed(2)} at '
      '${searchCheck.minAt} (nearest ${_obsName(searchCheck.minId)})');
  w('crossings into ridge fills: ${searchCheck.entries}; deepest penetration '
      '${searchCheck.deepest.toStringAsFixed(2)} at ${searchCheck.deepestAt}');
  w('min letter clearance ${searchCheck.minLetter.toStringAsFixed(2)} at '
      '${searchCheck.minLetterAt}');
  expect(searchCheck.entries, 0, reason: 'implemented route must not enter a ridge');
  expect(searchCheck.minClear, greaterThanOrEqualTo(6.5));
  expect(searchCheck.minLetter, greaterThanOrEqualTo(6.5));
  for (final p in searchCheck.entryPoints) {
    w('  ridge entry at ${p.dx.toStringAsFixed(1)}, ${p.dy.toStringAsFixed(1)}');
  }

  // --- ridge/gap breakdown: fill-to-fill minimum distances ---
  final dEach = [for (final m in masks.obstacles) _chamfer(m)];
  double fillGap(int a, int b) {
    var best = double.infinity;
    final mb = masks.obstacles[b];
    final da = dEach[a];
    for (var i = 0; i < mb.length; i++) {
      if (mb[i] != 0 && da[i] < best) best = da[i];
    }
    return best;
  }

  w('');
  w('== RIDGE/GAP BREAKDOWN (min fill-to-fill distance, units) ==');
  const pairs = [
    [0, 1], [1, 2], [2, 3], [3, 4], [4, 5],
    [5, 6], [6, 7], [7, 8], [5, 9], [7, 9], [8, 9],
  ];
  for (final pr in pairs) {
    w('${kObstacleNames[pr[0]]} <-> ${kObstacleNames[pr[1]]}: '
        '${fillGap(pr[0], pr[1]).toStringAsFixed(1)}');
  }

  // --- connectivity: entry point -> official route start, per margin ---
  const entry = Offset(596, 1260);
  final join = built.join;
  final eX = (entry.dx - aX0).round();
  final eY = (entry.dy - aY0).round();
  final jX = (join.dx - aX0).round();
  final jY = (join.dy - aY0).round();
  w('');
  w('== CONNECTIVITY (entry 596,1260 -> kit route start, free-grid margin +1) ==');
  var maxConn = 0.0;
  for (var m = 2.0; m <= 8.01; m += 0.5) {
    final free = _freeGrid(masks, m);
    final eid = _nearestFree(free, eX, eY);
    final jid = _nearestFree(free, jX, jY);
    final ok = eid >= 0 && jid >= 0 && _connected(free, eid, jid);
    w('margin ${m.toStringAsFixed(1)}: ${ok ? 'CONNECTED' : 'blocked'}');
    if (ok) maxConn = m;
  }
  w('max connected margin ${maxConn.toStringAsFixed(1)}');

  // --- channel route search ---
  w('');
  w('== CHANNEL ROUTE SEARCH ==');
  List<Offset>? bestWps;
  var bestMin = -1.0;
  var bestMargin = 0.0;
  for (final margin in kMargins) {
    if (margin > maxConn + 0.01) {
      w('margin ${margin.toStringAsFixed(1)}: skipped (not connected)');
      continue;
    }
    final free = _freeGrid(masks, margin);
    final eid = _nearestFree(free, eX, eY);
    final jid = _nearestFree(free, jX, jY);
    if (eid < 0 || jid < 0) {
      w('margin ${margin.toStringAsFixed(1)}: no free start/end');
      continue;
    }
    final raw = _astar(
        free, masks.dObs, _gx(eid), _gy(eid), _gx(jid), _gy(jid), margin);
    if (raw == null) {
      w('margin ${margin.toStringAsFixed(1)}: A* found no path');
      continue;
    }
    raw[0] = entry;
    raw[raw.length - 1] = join;
    var rawMin = double.infinity;
    for (final p in raw) {
      final d = masks.dObsAt(p);
      if (d < rawMin) rawMin = d;
    }
    w('margin ${margin.toStringAsFixed(1)}: raw ${raw.length} cells, grid min '
        'clearance ${rawMin.toStringAsFixed(1)}');
    final simp = _rdp(raw, 1.8);
    final trimmed = List<Offset>.of(simp);
    while (trimmed.length > 2 && (trimmed.last - join).distance < 36) {
      trimmed.removeLast();
    }
    final resampled = _resamplePolyline(trimmed, 82);
    var wps = List<Offset>.of(resampled);
    if (wps.length > 1 && (wps.last - join).distance < 24) wps.removeLast();
    if (wps.length < 2) wps = List<Offset>.of(trimmed);
    final refined =
        _refineWaypoints(wps, raw, margin, obs, letters, masks);
    final fc = refined.check;
    w('margin ${margin.toStringAsFixed(1)}: refined to ${refined.wps.length} '
        'waypoints; exact min clearance ${fc.minClear.toStringAsFixed(2)} at '
        '${fc.minAt} (nearest ${kObstacleNames[fc.minId]})');
    if (fc.minClear > bestMin) {
      bestMin = fc.minClear;
      bestWps = refined.wps;
      bestMargin = margin;
    }
    if (fc.minClear >= margin - 0.05) break;
  }

  _PathCheck? proposalCheck;
  _SearchBuild? proposalBuild;
  if (bestWps != null) {
    proposalBuild = _buildSearch(bestWps);
    final searchSamples = <Offset>[];
    final legChecks = <_PathCheck>[];
    for (final leg in proposalBuild.legs) {
      final ss = _sample(leg, 0.25);
      searchSamples.addAll(ss);
      legChecks.add(_checkPath(ss, obs, letters, masks));
    }
    final fc = _checkPath(searchSamples, obs, letters, masks);
    proposalCheck = fc;
    w('');
    w('== PROPOSED CHANNEL-LOCKED SEARCH (attempt margin '
        '${bestMargin.toStringAsFixed(1)}) ==');
    final wpLit = StringBuffer();
    for (final p in bestWps) {
      wpLit.write('Offset(${p.dx.toStringAsFixed(1)}, '
          '${p.dy.toStringAsFixed(1)}), ');
    }
    w('waypoints (${bestWps.length}):');
    w(wpLit.toString());
    final len = proposalBuild.full.computeMetrics().fold<double>(
        0, (a, m) => a + m.length);
    w('search length ${len.toStringAsFixed(0)}u (current authored: '
        '${built.full.computeMetrics().fold<double>(0, (a, m) => a + m.length).toStringAsFixed(0)}u)');
    w('exact min clearance ${fc.minClear.toStringAsFixed(2)} at ${fc.minAt} '
        '(nearest ${_obsName(fc.minId)})');
    w('inside fills: ${fc.entries} entries; deepest '
        '${fc.deepest.toStringAsFixed(2)}');
    w('min letter clearance ${fc.minLetter.toStringAsFixed(2)} at '
        '${fc.minLetterAt}');
    w('worst two-side balance '
        '${fc.minBalance.toStringAsFixed(2)} at ${fc.minBalanceAt}');
    for (var i = 0; i < legChecks.length; i++) {
      final lc = legChecks[i];
      w('  leg ${i + 1}: min ${lc.minClear.toStringAsFixed(2)} at ${lc.minAt} '
          '(nearest ${_obsName(lc.minId)})');
    }
    final combined =
        _checkPath([...searchSamples, ...routeSamples], obs, letters, masks);
    w('COMBINED animated line (search + kit route) min clearance '
        '${combined.minClear.toStringAsFixed(2)} at ${combined.minAt}');
    final runs = _describeRuns(searchSamples, obs);
    w('corridor runs:');
    for (final r in runs) {
      w('  $r');
    }
    final legLens = proposalBuild.legs
        .map((l) => l.computeMetrics().fold<double>(0, (a, m) => a + m.length))
        .toList();
    final totalLen = legLens.fold<double>(0, (a, b) => a + b);
    const budget = 4.32; // settleEnd 0.40 -> 4.72 covers the search legs
    var acc = 0.40;
    final windows = <double>[];
    for (final l in legLens) {
      acc += budget * l / totalLen;
      windows.add(double.parse(acc.toStringAsFixed(2)));
    }
    w('suggested leg end windows (s): ${windows.join(', ')}');
  } else {
    w('NO channel route found at any attempted margin — geometry limitation.');
  }

  await _writeDiagrams(
    masks,
    obs,
    letters,
    proposalBuild: proposalBuild,
    proposalWps: bestWps,
    currentBuild: built,
    searchCheck: searchCheck,
    proposalCheck: proposalCheck,
  );

  // --- experiment: channel-preferring cost (rides the ridge network) ---
  _SearchBuild? variantBuild;
  _PathCheck? variantCheck;
  {
    _channelCost = true;
    try {
      const vMargin = 6.5;
      final vfree = _freeGrid(masks, vMargin);
      final vEid = _nearestFree(vfree, eX, eY);
      final vJid = _nearestFree(vfree, jX, jY);
      if (vEid < 0 || vJid < 0) {
        w('channel variant: no free endpoints');
      } else {
        final vRaw = _astar(vfree, masks.dObs, _gx(vEid), _gy(vEid),
            _gx(vJid), _gy(vJid), vMargin);
        if (vRaw == null) {
          w('channel variant: A* found no path');
        } else {
          vRaw[0] = entry;
          vRaw[vRaw.length - 1] = join;
          final vSimp = _rdp(vRaw, 1.8);
          final vTrim = List<Offset>.of(vSimp);
          while (vTrim.length > 2 && (vTrim.last - join).distance < 36) {
            vTrim.removeLast();
          }
          var vWps = _resamplePolyline(vTrim, 82);
          if (vWps.length > 1 && (vWps.last - join).distance < 24) {
            vWps.removeLast();
          }
          if (vWps.length < 2) vWps = List<Offset>.of(vTrim);
          final vRef =
              _refineWaypoints(vWps, vRaw, vMargin, obs, letters, masks);
          variantBuild = _buildSearch(vRef.wps);
          variantCheck = vRef.check;
          final vLit = StringBuffer();
          for (final p in vRef.wps) {
            vLit.write('Offset(${p.dx.toStringAsFixed(1)}, '
                '${p.dy.toStringAsFixed(1)}), ');
          }
          w('');
          w('== CHANNEL-PREFERENCE VARIANT (cost band 8-18u, margin 6.5) ==');
          w('waypoints (${vRef.wps.length}):');
          w(vLit.toString());
          w('exact min clearance '
              '${vRef.check.minClear.toStringAsFixed(2)} at '
              '${vRef.check.minAt} (nearest ${_obsName(vRef.check.minId)})');
          w('inside fills: ${vRef.check.entries} entries; deepest '
              '${vRef.check.deepest.toStringAsFixed(2)}');
          w('min letter clearance ${vRef.check.minLetter.toStringAsFixed(2)}');
          w('worst two-side balance '
              '${vRef.check.minBalance.toStringAsFixed(2)} at '
              '${vRef.check.minBalanceAt}');
          w('length '
              '${variantBuild.full.computeMetrics().fold<double>(0, (a, m) => a + m.length).toStringAsFixed(0)}u');
        }
      }
    } finally {
      _channelCost = false;
    }
  }

  final vb = variantBuild;
  if (vb != null) {
    final vchk = variantCheck!;
    await _writePng('05-variant-channel.png', aW, 1115, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), 1115),
          Paint()..color = const Color(0xFF101A33));
      c.translate(-aX0, -aY0);
      _drawArt(c,
          ribbonAlpha: 0.30,
          letterAlpha: 0.22,
          hole: const Color(0xFF101A33));
      _drawRouteKit(c);
      if (proposalBuild != null) {
        _drawSearch(c, proposalBuild.full,
            color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
            width: 3.4);
      }
      _drawSearch(c, vb.full, color: Colors.white, width: 4.4);
      c.drawCircle(vb.join, 5, Paint()..color = Colors.white);
      c.drawCircle(const Offset(596, 1260), 5, Paint()..color = Colors.white);
      c.translate(aX0, aY0);
      _label(
          c,
          'CHANNEL-preference variant — min ridge clearance '
          '${vchk.minClear.toStringAsFixed(1)}u, fills entered ${vchk.entries}',
          const Offset(20, 14),
          color: const Color(0xFFFFE9A8));
      _label(
          c, 'white = variant; amber = primary proposal; green = kit route',
          const Offset(20, 44),
          color: const Color(0xFFBFE3FF), size: 15);
    });
  }

  // ==========================================================================
  // ROUND 5 — maze-feel metrics, channel reachability, the channel-riding
  // alternative, and real-paint ink/glow checks against the ridge fills.
  // ==========================================================================

  // --- what counts as a genuine groove: free space pinched between ridges ---
  final dMin = Float32List(aW * aH);
  final dSecond = Float32List(aW * aH);
  for (var i = 0; i < dMin.length; i++) {
    var m1 = double.infinity;
    var m2 = double.infinity;
    for (final da in dEach) {
      final v = da[i];
      if (v < m1) {
        m2 = m1;
        m1 = v;
      } else if (v < m2) {
        m2 = v;
      }
    }
    dMin[i] = m1;
    dSecond[i] = m2;
  }
  final free65 = _freeGrid(masks, 6.5);
  final chan = Uint8List(aW * aH);
  for (var i = 0; i < chan.length; i++) {
    if (free65[i] == 0) continue;
    if (dMin[i] > 30 || dSecond[i] > 60) continue;
    if (dMin[i] / math.max(dSecond[i], 0.6) < 0.30) continue;
    chan[i] = 1;
  }
  var chanCells = 0;
  for (final v in chan) {
    if (v != 0) chanCells++;
  }
  w('');
  w('== GENUINE GROOVES (free space pinched between two ridges, margin 6.5) ==');
  w('groove cells: $chanCells of ${aW * aH}');

  // --- maze-feel metrics on every candidate so far (incl. the intro test's
  // own turn metric, so a predicted regression is visible here first) ---
  w('');
  w('== MAZE-FEEL METRICS ==');
  void metricLine(String name, Path p) {
    final len = p.computeMetrics().fold<double>(0, (a, m) => a + m.length);
    final feel = _routeFeel(p, masks, chan);
    w('$name: length ${len.toStringAsFixed(0)}u; turns ${_turnCount(p)}; '
        '${(feel.near * 100).toStringAsFixed(0)}% within 30u of a ridge; '
        '${(feel.chan * 100).toStringAsFixed(0)}% inside genuine grooves');
  }

  metricLine('current authored', built.full);
  if (proposalBuild != null) metricLine('proposal', proposalBuild.full);
  if (variantBuild != null) metricLine('channel-variant', variantBuild.full);

  // --- channel reach: how far does the join mouth's groove system extend,
  // and where does it first touch open space on the way from the entry? ---
  final comp = Uint8List(aW * aH);
  int fillComponent(Uint8List mask, Uint8List out, int seed) {
    if (seed < 0 || mask[seed] == 0) return 0;
    final queue = <int>[seed];
    out[seed] = 1;
    var head = 0;
    var count = 1;
    while (head < queue.length) {
      final cur = queue[head++];
      final x = cur % aW;
      final y = cur ~/ aW;
      void visit(int n) {
        if (mask[n] != 0 && out[n] == 0) {
          out[n] = 1;
          count++;
          queue.add(n);
        }
      }

      if (x > 0) visit(cur - 1);
      if (x < aW - 1) visit(cur + 1);
      if (y > 0) visit(cur - aW);
      if (y < aH - 1) visit(cur + aW);
    }
    return count;
  }

  const pinchP = Offset(354.2, 766.6);
  final pinchSeed =
      _nearestFree(chan, (pinchP.dx - aX0).round(), (pinchP.dy - aY0).round());
  final compCells = fillComponent(chan, comp, pinchSeed);
  w('');
  w('== CHANNEL REACH (groove component through the join mouth) ==');
  w('component cells: $compCells');
  Offset? altTarget;
  if (compCells > 0) {
    // Open-space (margin 6.5) distance from the entry to every free cell.
    final dist65 = Int32List(aW * aH);
    dist65.fillRange(0, dist65.length, -1);
    final eSeed = _nearestFree(free65, eX, eY);
    final q = <int>[eSeed];
    dist65[eSeed] = 0;
    var head = 0;
    while (head < q.length) {
      final cur = q[head++];
      final x = cur % aW;
      final y = cur ~/ aW;
      final dv = dist65[cur] + 1;
      void visit(int n) {
        if (free65[n] != 0 && dist65[n] == -1) {
          dist65[n] = dv;
          q.add(n);
        }
      }

      if (x > 0) visit(cur - 1);
      if (x < aW - 1) visit(cur + 1);
      if (y > 0) visit(cur - aW);
      if (y < aH - 1) visit(cur + aW);
    }
    var bestOpen = 1 << 30;
    Offset bestOpenAt = Offset.zero;
    var lowestY = -1.0;
    Offset lowestAt = Offset.zero;
    for (var i = 0; i < comp.length; i++) {
      if (comp[i] == 0) continue;
      final p = Offset(aX0 + (i % aW) + 0.5, aY0 + (i ~/ aW) + 0.5);
      final dOpen = dist65[i];
      if (dOpen >= 0 && dOpen < bestOpen) {
        bestOpen = dOpen;
        bestOpenAt = p;
      }
      if (p.dy > lowestY) {
        lowestY = p.dy;
        lowestAt = p;
      }
    }
    // Geodesic depth of the component, measured from the pinch itself.
    final distC = Int32List(aW * aH);
    distC.fillRange(0, distC.length, -1);
    final qc = <int>[pinchSeed];
    distC[pinchSeed] = 0;
    var hc = 0;
    var farD = 0;
    var farCell = pinchSeed;
    while (hc < qc.length) {
      final cur = qc[hc++];
      final x = cur % aW;
      final y = cur ~/ aW;
      final dv = distC[cur] + 1;
      void visit(int n) {
        if (comp[n] != 0 && distC[n] == -1) {
          distC[n] = dv;
          if (dv > farD) {
            farD = dv;
            farCell = n;
          }
          qc.add(n);
        }
      }

      if (x > 0) visit(cur - 1);
      if (x < aW - 1) visit(cur + 1);
      if (y > 0) visit(cur - aW);
      if (y < aH - 1) visit(cur + aW);
    }
    w('  first groove touch from open space (coming from the entry): '
        '$bestOpenAt (open path ${bestOpen}u)');
    w('  lowest reachable groove cell: $lowestAt');
    w('  geodesic reach from the mouth pinch: ${farD}u to '
        '${Offset(aX0 + (farCell % aW) + 0.5, aY0 + (farCell ~/ aW) + 0.5)}');
    altTarget = bestOpenAt;
  }

  // --- channel-riding alternative: entry -> first groove touch -> join ---
  _SearchBuild? altBuild;
  _PathCheck? altCheck;
  if (altTarget != null && pinchSeed >= 0) {
    final aEid = _nearestFree(free65, eX, eY);
    final gSeed = _nearestFree(comp, (altTarget.dx - aX0).floor(),
        (altTarget.dy - aY0).floor());
    final jSeed = _nearestFree(comp, jX, jY);
    final rawA = (aEid < 0 || gSeed < 0)
        ? null
        : _astar(free65, masks.dObs, _gx(aEid), _gy(aEid), _gx(gSeed),
            _gy(gSeed), 6.5);
    final rawB = (gSeed < 0 || jSeed < 0)
        ? null
        : _astar(comp, masks.dObs, _gx(gSeed), _gy(gSeed), _gx(jSeed),
            _gy(jSeed), 6.5);
    if (rawA != null && rawB != null) {
      final raw = <Offset>[...rawA, ...rawB.skip(1)];
      raw[0] = entry;
      raw[raw.length - 1] = join;
      var altRawMin = double.infinity;
      for (final p in raw) {
        final d = masks.dObsAt(p);
        if (d < altRawMin) altRawMin = d;
      }
      w('');
      w('== CHANNEL-RIDING ALTERNATIVE (enter grooves at the first touch) ==');
      w('raw grid path: ${rawA.length} + ${rawB.length} cells; grid min '
          'clearance ${altRawMin.toStringAsFixed(1)}');
      final simp = _rdp(raw, 1.8);
      final trimmed = List<Offset>.of(simp);
      while (trimmed.length > 2 && (trimmed.last - join).distance < 36) {
        trimmed.removeLast();
      }
      var wps2 = _resamplePolyline(trimmed, 82);
      if (wps2.length > 1 && (wps2.last - join).distance < 24) {
        wps2.removeLast();
      }
      if (wps2.length < 2) wps2 = List<Offset>.of(trimmed);
      final refined = _refineWaypoints(wps2, raw, 6.5, obs, letters, masks);
      altBuild = _buildSearch(refined.wps);
      altCheck = refined.check;
      final lit = StringBuffer();
      for (final p in refined.wps) {
        lit.write('Offset(${p.dx.toStringAsFixed(1)}, '
            '${p.dy.toStringAsFixed(1)}), ');
      }
      w('waypoints (${refined.wps.length}):');
      w(lit.toString());
      w('exact min clearance ${refined.check.minClear.toStringAsFixed(2)} at '
          '${refined.check.minAt} (nearest ${_obsName(refined.check.minId)})');
      w('inside fills: ${refined.check.entries} entries; deepest '
          '${refined.check.deepest.toStringAsFixed(2)}');
      w('min letter clearance ${refined.check.minLetter.toStringAsFixed(2)}');
      metricLine('channel-riding alt', altBuild.full);
      final aLegLens = altBuild.legs
          .map((l) => l.computeMetrics().fold<double>(0, (a, m) => a + m.length))
          .toList();
      final aTotalLen = aLegLens.fold<double>(0, (a, b) => a + b);
      var aAcc = 0.40;
      final aWindows = <double>[];
      for (final l in aLegLens) {
        aAcc += 4.32 * l / aTotalLen;
        aWindows.add(double.parse(aAcc.toStringAsFixed(2)));
      }
      w('suggested leg end windows (s): ${aWindows.join(', ')}');
      for (final r in _describeRuns(_sample(altBuild.full, 0.25), obs)) {
        w('  rides $r');
      }
    } else {
      w('');
      w('channel-riding alternative: no open-space connection into the '
          'groove component.');
    }
  }

  // --- candidate sweep shapes: deliberate turns in the open canvas, feeding
  // the same groove entrance. Each is measured with the widget construction
  // plus refine-by-insertion (raw guide = its own dense polyline).
  w('');
  w('== SWEEP CANDIDATE SHAPES ==');
  final grooveEntry = <Offset>[
    const Offset(318.7, 824.3),
    const Offset(358.7, 765.4),
  ];
  final candidates = <String, List<Offset>>{
    'C1 hook + sweep + probe': [
      const Offset(596, 1260),
      const Offset(760, 1178),
      const Offset(430, 1140),
      const Offset(262, 1040),
      const Offset(383, 908),
      const Offset(300, 880),
      ...grooveEntry,
    ],
    'C2 sweep + probe': [
      const Offset(596, 1260),
      const Offset(430, 1150),
      const Offset(262, 1045),
      const Offset(383, 908),
      const Offset(298, 878),
      ...grooveEntry,
    ],
    'C3 hook + tame sweep + probe': [
      const Offset(596, 1260),
      const Offset(700, 1185),
      const Offset(420, 1150),
      const Offset(258, 1040),
      const Offset(383, 908),
      const Offset(298, 878),
      ...grooveEntry,
    ],
    'C4 deep probe apex': [
      const Offset(596, 1260),
      const Offset(430, 1150),
      const Offset(262, 1045),
      const Offset(394, 914),
      const Offset(296, 874),
      ...grooveEntry,
    ],
    'D1 hook + sweep + soft probe': [
      const Offset(596, 1260),
      const Offset(750, 1180),
      const Offset(430, 1145),
      const Offset(262, 1050),
      const Offset(332, 935),
      const Offset(290, 880),
      ...grooveEntry,
    ],
    'D2 soft probe tamer': [
      const Offset(596, 1260),
      const Offset(750, 1180),
      const Offset(430, 1145),
      const Offset(262, 1050),
      const Offset(322, 940),
      const Offset(292, 884),
      ...grooveEntry,
    ],
    'D3 no probe (control)': [
      const Offset(596, 1260),
      const Offset(750, 1180),
      const Offset(430, 1145),
      const Offset(262, 1050),
      const Offset(298, 878),
      ...grooveEntry,
    ],
  };
  for (final entry in candidates.entries) {
    final probeBuild = _buildSearch(entry.value);
    final rawGuide =
        _resamplePolyline(<Offset>[...entry.value, probeBuild.join], 8.0);
    final refinedC =
        _refineWaypoints(entry.value, rawGuide, 6.5, obs, letters, masks);
    final bc = _buildSearch(refinedC.wps);
    final dLens = bc.legs
        .map((l) => l.computeMetrics().fold<double>(0, (a, m) => a + m.length))
        .toList();
    final dTotal = dLens.fold<double>(0, (a, b) => a + b);
    var dAcc = 0.40;
    final dWin = <double>[];
    for (final l in dLens) {
      dAcc += 4.32 * l / dTotal;
      dWin.add(double.parse(dAcc.toStringAsFixed(2)));
    }
    final lenC =
        bc.full.computeMetrics().fold<double>(0, (a, m) => a + m.length);
    final feelC = _routeFeel(bc.full, masks, chan);
    w('${entry.key}: ${refinedC.wps.length} wp; min clearance '
        '${refinedC.check.minClear.toStringAsFixed(2)} at '
        '${refinedC.check.minAt} (${_obsName(refinedC.check.minId)}); '
        'entries ${refinedC.check.entries}; letters '
        '${refinedC.check.minLetter.toStringAsFixed(1)}u; length '
        '${lenC.toStringAsFixed(0)}u; turns ${_turnCount(bc.full)}; '
        '${(feelC.near * 100).toStringAsFixed(0)}% near; '
        '${(feelC.chan * 100).toStringAsFixed(0)}% groove');
    w('  legs ${dLens.map((l) => l.toStringAsFixed(0)).join(', ')}u; '
        'windows ${dWin.join(', ')}');
  }

  // Final evidence depicts the implemented user-green route, not a legacy candidate.
  final finalBuild = built;
  final finalCheck = searchCheck;
  w('');
  w('== IMPLEMENTED CANDIDATE: user-green inner-channel route ==');

  // --- rendered ink + glow vs the ridge fills, with the real paint settings.
  w('');
  w('== RENDERED INK / GLOW (stroke 5u, round caps; blur 1.1 where stated) ==');
  await _reportInkGap(
      'current authored line + glow', built.full, masks, obs, w,
      blur: true);
  await _reportInkGap(
      'implemented candidate ink core', finalBuild.full, masks, obs, w,
      blur: false);
  await _reportInkGap('implemented candidate + glow', finalBuild.full, masks, obs, w,
      blur: true);
  await _reportInkGap('previous HEAD route + glow',
      _buildSearch(kPreviousWaypoints).full, masks, obs, w, blur: true);
  await _reportInkGap(
      'official kit route + glow', FieldSyncLogoGeometry.route, masks, obs, w,
      blur: true);
  await _reportFillOverlap(
      'official kit route stroke (5u) vs ridges', FieldSyncLogoGeometry.route,
      masks, w,
      strokeWidth: 5);
  await _reportFillOverlap(
      'official kit arrowhead fill vs ridges',
      FieldSyncLogoGeometry.routeArrowhead, masks, w);

  // --- diagram 06: the channel-riding alternative vs the proposal.
  if (altBuild != null && altTarget != null) {
    final ac = altCheck!;
    await _writePng('06-channel-alt.png', aW, 1115, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), 1115),
          Paint()..color = const Color(0xFF101A33));
      c.translate(-aX0, -aY0);
      _drawArt(c,
          ribbonAlpha: 0.30,
          letterAlpha: 0.22,
          hole: const Color(0xFF101A33));
      _drawRouteKit(c);
      if (proposalBuild != null) {
        _drawSearch(c, proposalBuild.full,
            color: const Color(0xFFF59E0B).withValues(alpha: 0.45), width: 3.4);
      }
      _drawSearch(c, altBuild!.full, color: Colors.white, width: 4.4);
      c.drawCircle(altBuild.join, 5, Paint()..color = Colors.white);
      c.drawCircle(entry, 5, Paint()..color = Colors.white);
      c.drawCircle(
          altTarget!,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF7DF9FF));
      c.translate(aX0, aY0);
      _label(
          c,
          'ALT-1 (not selected): clearance ${ac.minClear.toStringAsFixed(1)}u; '
          '${ac.entries} fill entries; ${_turnCount(altBuild.full)} turns',
          const Offset(20, 14),
          color: const Color(0xFFFFE9A8));
      _label(c,
          'white = alt; amber = primary proposal; green = kit route; '
          'cyan ring = first groove touch',
          const Offset(20, 44),
          color: const Color(0xFFBFE3FF), size: 15);
    });
  }

  // --- diagram 07: ridges / genuine corridors / both routes.
  await _writePng('07-corridors.png', aW, aH, (c) {
    c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()),
        Paint()..color = const Color(0xFFF3F7FD));
    c.translate(-aX0, -aY0);
    for (var y = 0; y < 1115; y += 4) {
      for (var x = 0; x < aW; x += 4) {
        final i = y * aW + x;
        if (chan[i] == 0) continue;
        final inComp = comp[i] != 0;
        c.drawRect(
            Rect.fromLTWH(aX0 + x.toDouble(), aY0 + y.toDouble(), 4, 4),
            Paint()
              ..color = (inComp
                      ? const Color(0xFF0F9D58)
                      : const Color(0xFFF59E0B))
                  .withValues(alpha: inComp ? 0.42 : 0.20));
      }
    }
    final navy = Paint()..color = const Color(0xFF10233F);
    for (final p in FieldSyncLogoGeometry.fingerprints) {
      c.drawPath(p, navy);
    }
    final navySoft =
        Paint()..color = const Color(0xFF10233F).withValues(alpha: 0.85);
    for (final p in FieldSyncLogoGeometry.wordmark) {
      c.drawPath(p, navySoft);
    }
    c.drawCircle(
      const Offset(
          FieldSyncLogoGeometry.pinEyeX, FieldSyncLogoGeometry.pinEyeY),
      FieldSyncLogoGeometry.pinEyeR,
      Paint()..color = const Color(0xFFF3F7FD),
    );
    _drawRouteKit(c);
    if (proposalBuild != null) {
      _drawSearch(c, proposalBuild.full,
          color: const Color(0xFFB45309), width: 3.2);
    }
    _drawSearch(c, built.full, color: const Color(0xFF2563EB), width: 4.6);
    c.drawCircle(built.join, 5, Paint()..color = const Color(0xFF2563EB));
    c.drawCircle(kCurrentWaypoints.first, 5,
        Paint()..color = const Color(0xFF2563EB));
    c.translate(aX0, aY0);
    _label(c,
        'CORRIDORS: navy ridges; green reachable groove; amber other grooves',
        const Offset(20, 14),
        color: const Color(0xFFD3E3FF));
    _label(c,
        'blue = user-green route; dark amber = old proposal; green = kit route',
        const Offset(20, 44),
        color: const Color(0xFFD3E3FF), size: 15);
  });

  // --- diagram 08: real-paint close-ups (route stroke + glow, the join, the
  // official arrowhead/dot) for the final candidate.
  {
    const pw2 = 400;
    const ph2 = 400;
    final fb = finalBuild;
    final fc = finalCheck;
    await _writePng('08-ink-closeups.png', pw2 * 3, ph2, (c) {
      void panel(int idx, Offset center, double zoom, String title,
          void Function(Canvas) extra) {
        final x0 = idx * pw2.toDouble();
        c.drawRect(Rect.fromLTWH(x0, 0, pw2.toDouble(), (ph2 - 34).toDouble()),
            Paint()..color = const Color(0xFF0B1220));
        c.save();
        c.clipRect(Rect.fromLTWH(x0, 0, pw2.toDouble(), (ph2 - 34).toDouble()));
        c.translate(x0 + pw2 / 2, (ph2 - 34) / 2);
        c.scale(zoom);
        c.translate(-center.dx, -center.dy);
        _drawArt(c, hole: const Color(0xFF0B1220));
        extra(c);
        c.restore();
        _label(c, title, Offset(x0 + 10, (ph2 - 26).toDouble()),
            size: 13, boxed: false);
      }

      final realGhost = Paint()
        ..color = const Color(0xD9FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
      panel(
          0,
          fc.minAt,
          4.5,
           'user-green: tightest point, 5u + 1.1 sigma glow',
          (c) {
         c.drawPath(fb.full, realGhost);
         _drawSearch(c, fb.full, color: Colors.white, width: 5);
        c.drawCircle(
            fc.minAt,
            9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = const Color(0xFFFFC24B));
      });
      panel(1, join, 3.2, 'C1 join onto the kit route start (real paint)',
          (c) {
        _drawRouteKit(c);
         c.drawPath(fb.full, realGhost);
         _drawSearch(c, fb.full, color: Colors.white, width: 5);
      });
      final ahc = FieldSyncLogoGeometry.routeArrowhead.getBounds().center;
      panel(2, ahc, 4.0, 'official arrowhead + dot (kit art, untouched)', (c) {
        _drawRouteKit(c);
      });
    });
  }

  _asciiMap(masks, currentPath: built.full, proposal: proposalBuild?.full, alt: altBuild?.full, join: join, entry: entry, w: w);

  File('$kOutDir\\report.txt').writeAsStringSync(log.toString());
  w('probe complete in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
  return parityMax;
}

// ---------------------------------------------------------------------------
// Diagram + map output
// ---------------------------------------------------------------------------

Future<void> _writePng(
    String name, int wpx, int hpx, void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final canvas =
      Canvas(rec, Rect.fromLTWH(0, 0, wpx.toDouble(), hpx.toDouble()));
  draw(canvas);
  final img = await rec.endRecording().toImage(wpx, hpx);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  File('$kOutDir\\$name').writeAsBytesSync(bd!.buffer.asUint8List());
}

void _label(Canvas c, String text, Offset at,
    {Color color = const Color(0xFFFFFFFF),
    double size = 17,
    bool boxed = true}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
             fontFamily: 'T6Evidence',
             color: color, fontSize: size, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout();
  if (boxed) {
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(at.dx - 6, at.dy - 3, tp.width + 12, tp.height + 6),
          const Radius.circular(6)),
      Paint()..color = const Color(0xD90B1220),
    );
  }
  tp.paint(c, at);
}

void _drawArt(Canvas c,
    {double ribbonAlpha = 1,
    double letterAlpha = 1,
    Color hole = const Color(0xFF1D4ED8)}) {
  final rib = Paint()..color = Colors.white.withValues(alpha: ribbonAlpha);
  for (final p in FieldSyncLogoGeometry.fingerprints) {
    c.drawPath(p, rib);
  }
  final let = Paint()..color = Colors.white.withValues(alpha: letterAlpha);
  for (final p in FieldSyncLogoGeometry.wordmark) {
    c.drawPath(p, let);
  }
  c.drawCircle(
    const Offset(FieldSyncLogoGeometry.pinEyeX, FieldSyncLogoGeometry.pinEyeY),
    FieldSyncLogoGeometry.pinEyeR,
    Paint()..color = hole,
  );
}

void _drawRouteKit(Canvas c) {
  c.drawPath(
      FieldSyncLogoGeometry.route,
      Paint()
        ..color = const Color(0xFF34D399)
        ..style = PaintingStyle.stroke
        ..strokeWidth = FieldSyncLogoGeometry.routeStrokeWidth
        ..strokeCap = StrokeCap.round);
  c.drawPath(FieldSyncLogoGeometry.routeArrowhead,
      Paint()..color = const Color(0xFF34D399));
  c.drawCircle(
      const Offset(
          FieldSyncLogoGeometry.siteDotX, FieldSyncLogoGeometry.siteDotY),
      FieldSyncLogoGeometry.siteDotR,
      Paint()..color = const Color(0xFFEF3B3B));
}

void _drawSearch(Canvas c, Path p,
    {Color color = const Color(0xFFFF5C5C), double width = 2.6}) {
  c.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
}

Future<void> _writeDiagrams(
  _Masks masks,
  _EdgeIndex obs,
  _EdgeIndex letters, {
  required _SearchBuild? proposalBuild,
  required List<Offset>? proposalWps,
  required _SearchBuild currentBuild,
  required _PathCheck searchCheck,
  required _PathCheck? proposalCheck,
}) async {
  // 01 — the current authored line with every ridge crossing marked.
  await _writePng('01-current-crossings.png', aW, 1115, (c) {
    c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), 1115),
        Paint()..color = const Color(0xFF1D4ED8));
    c.translate(-aX0, -aY0);
    _drawArt(c);
    _drawRouteKit(c);
    _drawSearch(c, currentBuild.full);
    final xp = Paint()
      ..color = const Color(0xFFFFD60A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    for (final p in searchCheck.entryPoints) {
      c.drawLine(p + const Offset(-7, -7), p + const Offset(7, 7), xp);
      c.drawLine(p + const Offset(-7, 7), p + const Offset(7, -7), xp);
    }
    c.translate(aX0, aY0);
    _label(
        c,
        'CURRENT authored search line — ${searchCheck.entries} ridge-fill '
        'entries (X), deepest ${searchCheck.deepest.toStringAsFixed(1)}u',
        const Offset(20, 14),
        color: const Color(0xFFFFC9C9));
    _label(c, 'official kit route + dot (green) — untouched reference',
        const Offset(20, 44),
        color: const Color(0xFFB7F5DA), size: 15);
  });

  // 02 — the proposed channel-locked search with pinch heat.
  await _writePng('02-proposed-route.png', aW, 1115, (c) {
    c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), 1115),
        Paint()..color = const Color(0xFF101A33));
    c.translate(-aX0, -aY0);
    for (var y = 0; y < 1115; y += 5) {
      for (var x = 0; x < aW; x += 5) {
        final i = y * aW + x;
        if (masks.obsUnion[i] != 0 || masks.letters[i] != 0) continue;
        final d = masks.dObs[i];
        if (d > 16) continue;
        final t = (d / 16).clamp(0.0, 1.0).toDouble();
        final col =
            Color.lerp(const Color(0xFFEF4444), const Color(0xFFFACC15), t)!
                .withValues(alpha: 0.10 + 0.30 * (1 - t));
        c.drawRect(
            Rect.fromLTWH(aX0 + x.toDouble(), aY0 + y.toDouble(), 5, 5),
            Paint()..color = col);
      }
    }
    _drawArt(c,
        ribbonAlpha: 0.30,
        letterAlpha: 0.22,
        hole: const Color(0xFF101A33));
    _drawRouteKit(c);
    if (proposalBuild != null) {
      _drawSearch(c, proposalBuild.full,
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 13);
      _drawSearch(c, proposalBuild.full, color: Colors.white, width: 5);
      c.drawCircle(proposalBuild.join, 5.5, Paint()..color = Colors.white);
      c.drawCircle(
          const Offset(596, 1260), 5.5, Paint()..color = Colors.white);
      if (proposalCheck != null) {
        c.drawCircle(
            proposalCheck.minAt,
            9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = const Color(0xFFFFE9A8));
      }
    }
    c.translate(aX0, aY0);
    final mcs = proposalCheck == null
        ? 'not found'
        : '${proposalCheck.minClear.toStringAsFixed(1)}u at '
            '${proposalCheck.minAt.dx.toStringAsFixed(0)},'
            '${proposalCheck.minAt.dy.toStringAsFixed(0)}';
    _label(
        c,
        'PROPOSED channel-locked search — min ridge clearance $mcs',
        const Offset(20, 14),
        color: const Color(0xFFFFE9A8));
    _label(
        c, 'heat = ridge proximity < 16u; green = official kit route + dot',
        const Offset(20, 44),
        color: const Color(0xFFBFE3FF), size: 15);
  });

  // 03 — free-space clearance map.
  await _writePng('03-free-space.png', aW, 1115, (c) {
    c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), 1115),
        Paint()..color = const Color(0xFFEFF4FB));
    c.translate(-aX0, -aY0);
    for (var y = 0; y < 1115; y += 5) {
      for (var x = 0; x < aW; x += 5) {
        final i = y * aW + x;
        if (masks.obsUnion[i] != 0 || masks.letters[i] != 0) continue;
        final t = (masks.dObs[i] / 40).clamp(0.0, 1.0).toDouble();
        c.drawRect(
            Rect.fromLTWH(aX0 + x.toDouble(), aY0 + y.toDouble(), 5, 5),
            Paint()
              ..color =
                  const Color(0xFF2563EB).withValues(alpha: 0.30 * (1 - t)));
      }
    }
    final navy = Paint()..color = const Color(0xFF10233F);
    for (final p in FieldSyncLogoGeometry.fingerprints) {
      c.drawPath(p, navy);
    }
    final navySoft =
        Paint()..color = const Color(0xFF10233F).withValues(alpha: 0.88);
    for (final p in FieldSyncLogoGeometry.wordmark) {
      c.drawPath(p, navySoft);
    }
    c.drawCircle(
      const Offset(FieldSyncLogoGeometry.pinEyeX,
          FieldSyncLogoGeometry.pinEyeY),
      FieldSyncLogoGeometry.pinEyeR,
      Paint()..color = const Color(0xFFEFF4FB),
    );
    _drawRouteKit(c);
    _drawSearch(c, currentBuild.full,
        color: const Color(0xFFDC2626), width: 2.2);
    if (proposalBuild != null) {
      _drawSearch(c, proposalBuild.full,
          color: const Color(0xFFB45309), width: 4.4);
    }
    c.translate(aX0, aY0);
    _label(
        c, 'FREE SPACE — tint depth = clearance to nearest ridge (40u range)',
        const Offset(20, 14),
        color: const Color(0xFFD3E3FF));
    _label(
        c, 'red = current authored line; amber = proposed; green = kit route',
        const Offset(20, 44),
        color: const Color(0xFFD3E3FF), size: 15);
  });

  // 04 — close-ups: pinch, join, first violation.
  const pw = 360;
  const ph = 380;
  await _writePng('04-closeups.png', pw * 3, ph, (c) {
    final pinch = proposalCheck?.minAt ?? const Offset(400, 709.5);
    final firstCross = searchCheck.minAt;
    void panel(int idx, Offset center, double zoom, String title,
        void Function(Canvas) extra) {
      final x0 = idx * pw.toDouble();
      c.drawRect(Rect.fromLTWH(x0, 0, pw.toDouble(), (ph - 34).toDouble()),
          Paint()..color = const Color(0xFF0B1220));
      c.save();
      c.clipRect(Rect.fromLTWH(x0, 0, pw.toDouble(), (ph - 34).toDouble()));
      c.translate(x0 + pw / 2, (ph - 34) / 2);
      c.scale(zoom);
      c.translate(-center.dx, -center.dy);
      _drawArt(c, hole: const Color(0xFF0B1220));
      extra(c);
      c.restore();
      _label(c, title, Offset(x0 + 10, (ph - 26).toDouble()),
          size: 14, boxed: false);
    }

    panel(
        0,
        pinch,
        4,
        'proposal tightest pinch '
        '${proposalCheck == null ? '-' : '${proposalCheck.minClear.toStringAsFixed(1)}u'}',
        (c) {
      if (proposalBuild != null) {
        _drawSearch(c, proposalBuild.full, color: Colors.white, width: 5);
      }
      c.drawCircle(
          pinch,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xFFFFC24B));
    });
    panel(1, currentBuild.join, 3, 'join: kit route start (394, 709.5)', (c) {
      _drawRouteKit(c);
      if (proposalBuild != null) {
        _drawSearch(c, proposalBuild.full, color: Colors.white, width: 5);
        c.drawCircle(currentBuild.join, 5, Paint()..color = Colors.white);
      }
    });
    panel(
        2,
        firstCross,
        3,
        'current line tightest clearance '
        '${searchCheck.minClear.toStringAsFixed(1)}u @ '
        '${firstCross.dx.toStringAsFixed(0)},${firstCross.dy.toStringAsFixed(0)}',
        (c) {
      _drawRouteKit(c);
      _drawSearch(c, currentBuild.full);
      c.drawCircle(
          firstCross,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xFFFFD60A));
    });
  });

  // 09 — before/after: the HEAD line (rejected) vs the implemented route.
  final previousBuild = _buildSearch(kPreviousWaypoints);
  final previousCheck =
      _checkPath(_sample(previousBuild.full, 0.2), obs, letters, masks);
  await _writePng('09-before-after.png', aW, aH, (c) {
    c.drawRect(Rect.fromLTWH(0, 0, aW.toDouble(), aH.toDouble()),
        Paint()..color = const Color(0xFF0B1020));
    c.translate(-aX0, -aY0);
    _drawArt(c);
    _drawRouteKit(c);
    _drawSearch(c, previousBuild.full,
        color: const Color(0xFFFF5C5C), width: 4.2);
    _drawSearch(c, currentBuild.full,
        color: const Color(0xFF34D399), width: 4.2);
    final xp = Paint()
      ..color = const Color(0xFFFFD60A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    for (final p in previousCheck.entryPoints) {
      c.drawLine(p + const Offset(-8, -8), p + const Offset(8, 8), xp);
      c.drawLine(p + const Offset(-8, 8), p + const Offset(8, -8), xp);
    }
    c.translate(aX0, aY0);
    _label(
        c,
        'BEFORE red (HEAD): ${previousCheck.entries} fill entries (X); '
        'max depth ${previousCheck.deepest.toStringAsFixed(1)}u; '
        'min edge ${previousCheck.minClear.toStringAsFixed(2)}u',
        const Offset(20, 14),
        color: const Color(0xFFFFC9C9));
    _label(
        c,
        'AFTER (green, implemented): ${searchCheck.entries} ridge-fill '
        'entries, min clearance ${searchCheck.minClear.toStringAsFixed(1)}u',
        const Offset(20, 44),
        color: const Color(0xFFB7F5DA),
        size: 15);
  });
}

void _asciiMap(
  _Masks masks, {
  Path? currentPath,
  Path? proposal,
  Path? alt,
  required Offset join,
  required Offset entry,
  required void Function(String) w,
}) {
  const cols = 88;
  const rows = 60;
  final cw = aW / cols;
  final ch = aH / rows;
  final grid =
      List<List<String>>.generate(rows, (_) => List<String>.filled(cols, ' '));
  for (var ry = 0; ry < rows; ry++) {
    for (var rx = 0; rx < cols; rx++) {
      final x = (aX0 + (rx + 0.5) * cw).floor() - aX0.toInt();
      final y = (aY0 + (ry + 0.5) * ch).floor() - aY0.toInt();
      final i = y.clamp(0, aH - 1).toInt() * aW + x.clamp(0, aW - 1).toInt();
      if (masks.obsUnion[i] != 0) {
        grid[ry][rx] = '#';
      } else if (masks.letters[i] != 0) {
        grid[ry][rx] = '=';
      } else if (masks.dObs[i] < 6.5) {
        grid[ry][rx] = '.';
      }
    }
  }
  void mark(Path? p, String marker) {
    if (p == null) return;
    for (final pt in _sample(p, 6.0)) {
      final rx = ((pt.dx - aX0) / cw).floor().clamp(0, cols - 1).toInt();
      final ry = ((pt.dy - aY0) / ch).floor().clamp(0, rows - 1).toInt();
      final cur = grid[ry][rx];
      if (cur == ' ' || cur == '.') grid[ry][rx] = marker;
    }
  }

  mark(currentPath, 'x');
  mark(proposal, 'P');
  mark(alt, 'A');
  var ry = ((join.dy - aY0) / ch).floor().clamp(0, rows - 1).toInt();
  var rx = ((join.dx - aX0) / cw).floor().clamp(0, cols - 1).toInt();
  grid[ry][rx] = 'J';
  ry = ((entry.dy - aY0) / ch).floor().clamp(0, rows - 1).toInt();
  rx = ((entry.dx - aX0) / cw).floor().clamp(0, cols - 1).toInt();
  grid[ry][rx] = 'E';
  ry = ((FieldSyncLogoGeometry.siteDotY - aY0) / ch)
      .floor()
      .clamp(0, rows - 1)
      .toInt();
  rx = ((FieldSyncLogoGeometry.siteDotX - aX0) / cw)
      .floor()
      .clamp(0, cols - 1)
      .toInt();
  grid[ry][rx] = 'D';
  w('');
  w('== ASCII map: # ridge fill, = letters, . clearance<6.5, '
      'x current line, P proposal, A alt, J join, E entry, D dot ==');
  for (final row in grid) {
    w(row.join());
  }
}
