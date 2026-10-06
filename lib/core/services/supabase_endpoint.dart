import 'dart:io';

/// Syntax-only validation: never resolve DNS or contact the endpoint.
String validateSupabaseEndpoint(String? value, {required bool release}) {
  const invalid = FormatException('Unsafe Supabase endpoint configuration.');
  if (value == null || value.isEmpty || value.trim() != value) throw invalid;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw invalid;
  }
  var host = uri.host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  final address = InternetAddress.tryParse(host);
  if (address == null &&
      (!host
              .split('.')
              .every(
                (label) => RegExp(
                  r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
                ).hasMatch(label),
              ) ||
          RegExp(r'^[0-9.]+$').hasMatch(host))) {
    throw invalid;
  }
  if (!release) return value;
  if (uri.scheme != 'https') throw invalid;
  if (address != null) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      // Reject ambiguous octal-style IPv4 spellings as well as local ranges.
      if (host
              .split('.')
              .any((part) => part.length > 1 && part.startsWith('0')) ||
          _privateIpv4(bytes)) {
        throw invalid;
      }
    } else {
      final mapped =
          bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 255 &&
          bytes[11] == 255;
      if (bytes.take(15).every((b) => b == 0) && bytes[15] <= 1 ||
          (bytes[0] & 0xfe) == 0xfc ||
          bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 ||
          bytes[0] == 0xff ||
          mapped && _privateIpv4(bytes.sublist(12))) {
        throw invalid;
      }
    }
  } else if (!host.contains('.') ||
      host == 'localhost' ||
      const [
        '.localhost',
        '.local',
        '.lan',
        '.internal',
        '.home',
        '.home.arpa',
        '.localdomain',
      ].any(host.endsWith)) {
    throw invalid;
  }
  return value;
}

bool _privateIpv4(List<int> b) =>
    b[0] == 0 ||
    b[0] == 10 ||
    b[0] == 127 ||
    b[0] == 169 && b[1] == 254 ||
    b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
    b[0] == 192 && b[1] == 168 ||
    b[0] == 100 && b[1] >= 64 && b[1] <= 127 ||
    b[0] >= 224;
