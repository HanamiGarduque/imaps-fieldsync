import 'site_location_reference_service.dart';

/// Read-only labels over the original, same-order evidence and metadata.
/// Legacy remote paths without usable notes cannot establish an evidence type.
class PhotoEvidencePresentation {
  final List<Map<String, dynamic>> photos;
  final List<int> _siteNumbers = [];
  late final int sitePhotoCount;
  late final int referenceCount;

  PhotoEvidencePresentation(
    this.photos, {
    bool requireMetadata = false,
    Set<int> capturedIndices = const {},
  }) {
    var sites = 0;
    var references = 0;
    for (final (index, photo) in photos.indexed) {
      final reference = isLocationReferencePhoto(photo);
      if (reference) references++;
      final note = (photo['notes'] as String?)?.trim() ?? '';
      final identified =
          !requireMetadata ||
          capturedIndices.contains(index) ||
          note.isNotEmpty;
      _siteNumbers.add(!reference && identified ? ++sites : 0);
    }
    sitePhotoCount = sites;
    referenceCount = references;
  }

  int get totalCount => photos.length;
  int get unclassifiedCount => totalCount - sitePhotoCount - referenceCount;
  bool isReferenceAt(int index) => isLocationReferencePhoto(photos[index]);
  bool isSitePhotoAt(int index) => _siteNumbers[index] > 0;

  String labelAt(int index, {bool includeTotal = false}) {
    if (isReferenceAt(index)) return 'Site Location Reference';
    if (isSitePhotoAt(index)) {
      return 'Photo ${_siteNumbers[index]}'
          '${includeTotal ? ' of $sitePhotoCount' : ''}';
    }
    return 'Evidence attachment ${index + 1}'
        '${includeTotal ? ' of $totalCount' : ''}';
  }

  String semanticsAt(int index) => isReferenceAt(index)
      ? 'View site location reference'
      : 'View ${labelAt(index).toLowerCase()}';
}
