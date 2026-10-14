import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as image;

/// Local HTTP responses for the real FlutterMap/RouteService in widget tests.
/// No request reaches a tile server, routing server or application backend.
class SiteMapHttpFixture extends HttpOverrides {
  SiteMapHttpFixture({this.tileDirectory, this.routeJson});

  final String? tileDirectory;
  String? routeJson;
  Future<String?> Function(Uri)? routeResponse;
  bool streetTilesAvailable = true;
  final requestedTiles = <String>{};
  final requestedRoutes = <Uri>[];
  static final _blankTile = image.encodePng(
    image.Image(width: 1, height: 1)..setPixelRgba(0, 0, 244, 246, 251, 255),
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client((uri) async {
    if (uri.host == 'router.project-osrm.org') {
      requestedRoutes.add(uri);
      final body = routeResponse == null
          ? routeJson
          : await routeResponse!(uri);
      return _Response(
        utf8.encode(body ?? '{}'),
        body == null ? 503 : 200,
        'application/json',
      );
    }
    if (uri.host != 'tile.openstreetmap.org') {
      throw StateError('Unexpected external request in map fixture: $uri');
    }
    final tile = 'tile-${uri.pathSegments.join('-')}';
    requestedTiles.add(tile);
    final file = tileDirectory == null || !streetTilesAvailable
        ? null
        : File('$tileDirectory/$tile');
    return _Response(
      file?.existsSync() == true ? file!.readAsBytesSync() : _blankTile,
      200,
      'image/png',
    );
  });
}

class _Client implements HttpClient {
  _Client(this.respond);
  final Future<_Response> Function(Uri) respond;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async =>
      _Request(respond(uri));
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => openUrl('GET', uri);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<_Response> response;
  @override
  final HttpHeaders headers = _Headers('application/json');
  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      stream.drain<void>();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes, this.statusCode, String type)
    : headers = _Headers(type);
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  int get contentLength => bytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Unavailable';
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers(this.type);
  final String type;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String, List<String>) action) =>
      action('content-type', [type]);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
