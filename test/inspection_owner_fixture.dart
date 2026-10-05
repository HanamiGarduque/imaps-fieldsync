import 'package:imaps_fieldsync/core/services/db_helper.dart';

/// Local-only inspector identity for persistence/replay fixtures that do not
/// initialize a Supabase session. Tests that need a real signed-in identity use
/// `signInInspector` from `inspector_reassignment_test.dart` instead.
const ownerFixture = 'fixture-inspector-owner';

void useOwnerFixture() => DBHelper.inspectorIdForTesting = ownerFixture;

void clearOwnerFixture() => DBHelper.inspectorIdForTesting = null;