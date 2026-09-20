import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../models/family_link.dart';
import '../services/beta_api_client.dart';

/// Holds every elderly connection this caregiver has. Screens that need
/// "the" elderly user being monitored read [primaryElderlyUser] - the spec's
/// own examples only ever show one at a time. Supporting more than one is
/// modeled here so a future "switch person" UI has something to switch
/// between, without every other screen needing to know about it yet.
class FamilyProvider extends ChangeNotifier {
  final BetaApiClient _api;
  FamilyProvider(this._api);

  bool isLoading = false;
  AppException? error;
  List<FamilyLink> links = [];
  List<CoCaregiver> coCaregivers = [];

  List<FamilyLink> get activeLinks => links.where((l) => l.status == RelationshipStatus.active).toList();

  FamilyLink? get primaryLink => activeLinks.isEmpty ? null : activeLinks.first;
  String? get primaryElderlyUserId => primaryLink?.elderlyUser.id;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      links = await _api.getFamilyLinks();
      final elderlyId = primaryElderlyUserId;
      if (elderlyId != null) {
        coCaregivers = await _api.getCoCaregivers(elderlyId);
      }
    } on AppException catch (e) {
      error = e;
    } catch (_) {
      error = const UnknownApiException();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> inviteElderly({required String invitationCode, required String relationshipLabel}) async {
    try {
      final link = await _api.inviteElderly(invitationCode: invitationCode, relationshipLabel: relationshipLabel);
      links = [...links, link];
      notifyListeners();
      return true;
    } on AppException catch (e) {
      error = e;
      notifyListeners();
      return false;
    }
  }

  Future<void> removeLink(String linkId) async {
    await _api.removeFamilyLink(linkId);
    links = links.where((l) => l.id != linkId).toList();
    notifyListeners();
  }
}
