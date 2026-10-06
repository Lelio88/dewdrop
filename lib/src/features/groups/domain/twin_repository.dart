/// Frontière du jumelage et des demandes d'adhésion (Supabase `group_twins`,
/// `group_join_requests` et leurs RPC, migration `20261006120000_group_twins`).
///
/// Invariants tenus par le serveur, reflétés par l'interface :
///  - seul le créateur d'un cercle jumelle, défait et tranche les demandes ;
///  - un code ne fait jamais entrer : [requestToJoin] envoie une demande ;
///  - un code inconnu et un refus (blocage) répondent pareil : `null` pour
///    [preview], [JoinRequestOutcome.invalid] pour [requestToJoin] ;
///  - le code donné à un jumeau ne se lit qu'au retour de [twinGroup].
library;

import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// Une erreur de jumelage ou de demande, déjà dite pour l'utilisateur. Dans
/// le domaine pour que le dépôt (qui la lève) et l'interface (qui l'affiche)
/// en dépendent sans traverser la couche data.
class TwinException implements Exception {
  const TwinException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ce qu'un code fait rejoindre, avant de demander.
final class JoinCodePreview {
  const JoinCodePreview({
    required this.groupId,
    required this.name,
    required this.creatorHandle,
    required this.isMember,
    required this.alreadyRequested,
  });

  final String groupId;
  final String name;

  /// Le @handle du créateur, à qui part la demande ; `null` s'il n'en a pas
  /// encore choisi.
  final String? creatorHandle;
  final bool isMember;
  final bool alreadyRequested;
}

/// La réponse du serveur à une demande d'adhésion.
enum JoinRequestOutcome {
  requested,
  alreadyRequested,
  alreadyMember,

  /// Code inconnu, défait, ou refusé — sans distinction, à dessein.
  invalid,
}

/// Une demande en attente dans un cercle que je crée.
final class JoinRequest {
  const JoinRequest({
    required this.groupId,
    required this.requester,
    required this.createdAt,
  });

  final String groupId;
  final Profile requester;
  final DateTime createdAt;
}

abstract interface class TwinRepository {
  /// Les jumeaux d'un cercle (membres et créateur).
  Future<List<GroupTwin>> twins(String groupId);

  /// Crée le jumeau avec [app], ou le complète de [remoteCode] ; rend le code
  /// du cercle à donner à l'autre app. Créateur seul.
  Future<String> twinGroup(String groupId, TwinApp app, {String? remoteCode});

  /// Défait le jumelage : son code n'ouvre plus rien. Créateur seul.
  Future<void> untwinGroup(String groupId, TwinApp app);

  /// Le cercle que [code] fait rejoindre, ou `null`.
  Future<JoinCodePreview?> preview(String code);

  /// Demande à entrer dans le cercle de [code].
  Future<JoinRequestOutcome> requestToJoin(String code);

  /// Les demandes en attente dans les cercles que je crée.
  Future<List<JoinRequest>> pendingRequests();

  /// Accepte ([accept]) ou refuse la demande de [userId]. Créateur seul.
  Future<void> answer(String groupId, String userId, {required bool accept});

  /// Un tick à chaque demande reçue, tranchée ou annulée (temps réel).
  Stream<int> watchRequests();
}
