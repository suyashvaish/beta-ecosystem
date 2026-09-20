import 'package:beta_care/models/medication_models.dart';
import 'package:beta_care/models/permission_set.dart';
import 'package:beta_care/models/status_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionSet', () {
    test('defaults to privacy-first: everything off, including conversations', () {
      const permissions = PermissionSet.none;
      expect(permissions.health, isFalse);
      expect(permissions.medication, isFalse);
      expect(permissions.location, isFalse);
      expect(permissions.activity, isFalse);
      expect(permissions.device, isFalse);
      expect(permissions.emergency, isFalse);
      expect(permissions.conversations, isFalse);
    });

    test('fromJson only turns on what the backend explicitly grants', () {
      final permissions = PermissionSet.fromJson({'health': true, 'medication': true});
      expect(permissions.health, isTrue);
      expect(permissions.medication, isTrue);
      expect(permissions.location, isFalse);
      expect(permissions.conversations, isFalse);
    });
  });

  group('combineStatusLevels', () {
    test('reports the single worst level among several signals', () {
      final result = combineStatusLevels([StatusLevel.normal, StatusLevel.unknown, StatusLevel.attention]);
      expect(result, StatusLevel.attention);
    });

    test('emergency always wins, even alongside normal signals', () {
      final result = combineStatusLevels([StatusLevel.normal, StatusLevel.normal, StatusLevel.emergency]);
      expect(result, StatusLevel.emergency);
    });

    test('an empty set of signals is unknown, not normal', () {
      expect(combineStatusLevels(const []), StatusLevel.unknown);
    });
  });

  group('MedicationStatus -> StatusLevel mapping', () {
    test('taken is never anything but normal', () {
      expect(MedicationStatus.taken.statusLevel, StatusLevel.normal);
    });

    test('missed and skipped both need attention', () {
      expect(MedicationStatus.missed.statusLevel, StatusLevel.attention);
      expect(MedicationStatus.skipped.statusLevel, StatusLevel.attention);
    });

    test('pending is unknown, not silently treated as fine', () {
      expect(MedicationStatus.pending.statusLevel, StatusLevel.unknown);
    });
  });
}
