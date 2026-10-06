/// Jumelage d'un cercle DewDrop avec un groupe d'une autre app du conteneur
/// (Agora, Arpente) : les apps jumelles, le jumeau d'un cercle, et les liens
/// du protocole commun (`docs/liens-inter-apps.md` du dépôt méta `Projets`).
///
/// Les apps ne se parlent pas : elles s'ouvrent l'une l'autre par des liens
/// préremplis, et la personne valide dans l'app d'arrivée.
///
/// Choix non évidents :
/// - les paramètres voyagent dans le **fragment** : un code ouvre un groupe,
///   et une requête finirait dans les journaux de l'hébergeur (GitHub Pages)
///   quand l'autre app n'est pas installée ;
/// - un lien reçu n'est jamais gardé tel quel : seuls l'app (liste fermée) et
///   un code validé par son format en sont tirés, et les adresses sont
///   reconstruites depuis la base fixe de l'app jumelle. Un lien forgé ne
///   peut donc envoyer personne vers un autre site ;
/// - le nom proposé est du texte : caractères de contrôle et de mise en
///   forme (dont l'inversion bidirectionnelle) retirés, 60 caractères au plus ;
/// - une réponse ne vaut que pour une demande partie de cet appareil depuis
///   moins de 24 h ([matchTwinRequest]) : ouvrir l'autre app peut faire
///   fermer DewDrop par Android, d'où une mémoire qui survit au processus.
///
/// Invariant : [parseTwinLink] rend `null` pour tout lien qu'il ne faut pas
/// suivre — jamais un lien à moitié valide.
///
/// ```dart
/// switch (parseTwinLink(params)) {
///   case TwinRequest(): // proposer de jumeler un cercle
///   case TwinResponse(): // compléter un jumelage lancé d'ici
///   case null: // lien à ignorer
/// }
/// ```
library;

import 'dart:convert';
import 'dart:math';

/// Le code d'un cercle DewDrop donné à un jumeau : 8 caractères, alphabet
/// sans ambiguïté (ni 0/O, ni 1/I).
final dewdropCodePattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

/// Les apps avec lesquelles un cercle peut se jumeler.
enum TwinApp {
  agora(displayName: 'Agora', codeLength: 8),
  arpente(displayName: 'Arpente', codeLength: 6);

  const TwinApp({required this.displayName, required this.codeLength});

  /// Nom de l'app, une marque.
  final String displayName;

  /// Longueur du code d'un groupe dans cette app.
  final int codeLength;

  /// La valeur de `de` (et de `group_twins.app`) qui désigne cette app.
  String get code => name;

  /// L'app désignée par [code], ou `null`.
  static TwinApp? fromCode(String? code) =>
      values.where((app) => app.code == code).firstOrNull;

  /// Un code de groupe de cette app, en majuscules.
  bool acceptsCode(String code) =>
      RegExp('^[A-HJ-NP-Z2-9]{$codeLength}\$').hasMatch(code);

  /// Rejoindre le groupe jumeau dans cette app.
  Uri joinUri(String code) => switch (this) {
    // Agora route « par dièse » : son écran d'adhésion est #/join/CODE.
    agora => Uri.parse('https://agora.heianenterprise.com/#/join/$code'),
    arpente => Uri.parse(
      'https://arpente.heianenterprise.com/rejoindre.html',
    ).replace(fragment: _query({'code': code})),
  };

  Uri _twinUri(Map<String, String> params) => switch (this) {
    agora => Uri.parse(
      'https://agora.heianenterprise.com/',
    ).replace(fragment: '/twin?${_query(params)}'),
    arpente => Uri.parse(
      'https://arpente.heianenterprise.com/jumeler.html',
    ).replace(fragment: _query(params)),
  };
}

/// Le jumeau d'un cercle dans une autre app, tel que ses membres le voient.
final class GroupTwin {
  const GroupTwin({required this.app, this.remoteCode});

  final TwinApp app;

  /// Le code pour rejoindre le groupe jumeau ; `null` tant que l'autre app
  /// n'a pas répondu.
  final String? remoteCode;

  bool get isPending => remoteCode == null;
}

/// Un lien de jumelage reçu d'une autre app, déjà validé.
sealed class TwinLink {
  const TwinLink({
    required this.app,
    required this.remoteCode,
    required this.state,
  });

  /// L'app qui envoie le lien.
  final TwinApp app;

  /// Le code pour rejoindre son groupe.
  final String remoteCode;

  /// Le jeton de l'app qui a lancé le jumelage, à renvoyer tel quel.
  final String state;
}

/// Une autre app propose de jumeler l'un de ses groupes avec un cercle.
final class TwinRequest extends TwinLink {
  const TwinRequest({
    required super.app,
    required super.remoteCode,
    required super.state,
    this.name,
  });

  /// Le nom proposé au cercle jumeau ; `null` s'il n'en reste rien.
  final String? name;
}

/// L'autre app répond à un jumelage lancé depuis DewDrop.
final class TwinResponse extends TwinLink {
  const TwinResponse({
    required super.app,
    required super.remoteCode,
    required super.state,
    required this.forCode,
  });

  /// Le code DewDrop envoyé dans la demande : il désigne le cercle.
  final String forCode;
}

final _stateToken = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// Lit les paramètres d'un lien de jumelage ; `null` s'il ne faut pas le
/// suivre.
TwinLink? parseTwinLink(Map<String, String> params) {
  final app = TwinApp.fromCode(params['de']);
  final code = params['code']?.trim().toUpperCase();
  final state = params['etat'];
  if (app == null ||
      code == null ||
      !app.acceptsCode(code) ||
      state == null ||
      !_stateToken.hasMatch(state)) {
    return null;
  }
  final forCode = params['pour']?.trim().toUpperCase();
  if (forCode != null) {
    if (!dewdropCodePattern.hasMatch(forCode)) return null;
    return TwinResponse(
      app: app,
      remoteCode: code,
      state: state,
      forCode: forCode,
    );
  }
  return TwinRequest(
    app: app,
    remoteCode: code,
    state: state,
    name: cleanTwinName(params['nom']),
  );
}

const _maxNameLength = 60;

/// Contrôle (Cc) et mise en forme (Cf : inversion bidirectionnelle, espaces
/// de largeur nulle) : rien de cela n'a sa place dans un nom de cercle.
final _hiddenCharacters = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

/// Un nom de groupe reçu par lien, réduit à du texte lisible ; `null` s'il
/// n'en reste rien.
String? cleanTwinName(String? raw) {
  if (raw == null) return null;
  final text = raw
      .replaceAll(_hiddenCharacters, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return null;
  final runes = text.runes;
  return runes.length <= _maxNameLength
      ? text
      : String.fromCharCodes(runes.take(_maxNameLength)).trimRight();
}

/// La demande que DewDrop envoie à [app] : demander à entrer dans ce cercle
/// avec [code], le jumeau à nommer [name].
Uri twinRequestUri(
  TwinApp app, {
  required String code,
  required String name,
  required String state,
}) => app._twinUri({'de': 'dewdrop', 'code': code, 'nom': name, 'etat': state});

/// La réponse de DewDrop à une demande de [app] pour son groupe [forCode].
Uri twinResponseUri(
  TwinApp app, {
  required String code,
  required String forCode,
  required String state,
}) => app._twinUri({
  'de': 'dewdrop',
  'code': code,
  'pour': forCode,
  'etat': state,
});

/// Un jeton neuf pour un jumelage lancé d'ici : 16 octets aléatoires, en
/// base64 URL sans remplissage (22 caractères).
String newTwinState([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Une demande de jumelage partie de cet appareil, en attente de la réponse
/// de l'autre app.
final class TwinRequestSent {
  const TwinRequestSent({
    required this.app,
    required this.groupId,
    required this.code,
    required this.sentAt,
  });

  final TwinApp app;
  final String groupId;

  /// Le code DewDrop envoyé : la réponse le rend dans `pour`.
  final String code;
  final DateTime sentAt;

  Map<String, Object> toJson() => {
    'app': app.code,
    'groupId': groupId,
    'code': code,
    'sentAt': sentAt.toUtc().toIso8601String(),
  };

  /// Relit [toJson] ; `null` pour une entrée illisible (format ancien, app
  /// retirée de la liste).
  static TwinRequestSent? fromJson(Map<String, Object?> json) {
    final app = TwinApp.fromCode(json['app'] as String?);
    final groupId = json['groupId'];
    final code = json['code'];
    final sentAt = DateTime.tryParse(json['sentAt'] as String? ?? '');
    if (app == null ||
        groupId is! String ||
        code is! String ||
        sentAt == null) {
      return null;
    }
    return TwinRequestSent(
      app: app,
      groupId: groupId,
      code: code,
      sentAt: sentAt,
    );
  }
}

/// Une réponse vaut 24 h : au-delà, on relance le jumelage.
const twinRequestLifetime = Duration(hours: 24);

/// La demande à laquelle répond [response] (même jeton, même app, même code,
/// pas périmée), ou `null`. Sans cette règle, un membre qui connaît le code
/// d'un jumeau pourrait forger une réponse et faire rattacher un groupe à lui.
TwinRequestSent? matchTwinRequest(
  Map<String, TwinRequestSent> requests,
  TwinResponse response,
  DateTime now,
) {
  final request = requests[response.state];
  if (request == null ||
      request.app != response.app ||
      request.code != response.forCode ||
      now.difference(request.sentAt) > twinRequestLifetime) {
    return null;
  }
  return request;
}

String _query(Map<String, String> params) => Uri(queryParameters: params).query;
