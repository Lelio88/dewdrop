import 'dart:math';

import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le protocole des liens entre apps (docs/liens-inter-apps.md du dépôt méta),
/// côté DewDrop : ce qu'on accepte d'un lien reçu, et les adresses qu'on ouvre.
void main() {
  const state = 'abcdefghijklmnop_-12';

  group('parseTwinLink', () {
    test('une demande d\'Agora : app, code en majuscules, nom nettoyé', () {
      final link = parseTwinLink({
        'de': 'agora',
        'code': 'abcd2345',
        'nom': '  Les\u202e   copains ',
        'etat': state,
      });
      expect(link, isA<TwinRequest>());
      final request = link! as TwinRequest;
      expect(request.app, TwinApp.agora);
      expect(request.remoteCode, 'ABCD2345');
      expect(request.name, 'Les copains');
      expect(request.state, state);
    });

    test('une demande d\'Arpente porte un code de 6 caractères', () {
      final link = parseTwinLink({
        'de': 'arpente',
        'code': 'QRS789',
        'etat': state,
      });
      expect((link! as TwinRequest).app, TwinApp.arpente);
      expect(link.remoteCode, 'QRS789');
    });

    test('un code au format d\'une autre app est refusé', () {
      expect(
        parseTwinLink({'de': 'arpente', 'code': 'ABCD2345', 'etat': state}),
        isNull,
      );
      expect(
        parseTwinLink({'de': 'agora', 'code': 'QRS789', 'etat': state}),
        isNull,
      );
    });

    test('un code aux caractères ambigus (0, O, 1, I) est refusé', () {
      expect(
        parseTwinLink({'de': 'agora', 'code': 'ABCD0123', 'etat': state}),
        isNull,
      );
    });

    test('une app hors liste, ou DewDrop elle-même, est refusée', () {
      for (final de in ['deckhand', 'dewdrop', '', 'AGORA']) {
        expect(
          parseTwinLink({'de': de, 'code': 'ABCD2345', 'etat': state}),
          isNull,
          reason: de,
        );
      }
    });

    test('un jeton absent ou mal formé fait ignorer le lien', () {
      expect(parseTwinLink({'de': 'agora', 'code': 'ABCD2345'}), isNull);
      for (final etat in ['court', 'a' * 65, 'avec espaces dedans!!']) {
        expect(
          parseTwinLink({'de': 'agora', 'code': 'ABCD2345', 'etat': etat}),
          isNull,
          reason: etat,
        );
      }
    });

    test('un lien avec pour est une réponse, pour au format DewDrop', () {
      final link = parseTwinLink({
        'de': 'agora',
        'code': 'ABCD2345',
        'pour': ' wxyz6789 ',
        'etat': state,
      });
      expect(link, isA<TwinResponse>());
      expect((link! as TwinResponse).forCode, 'WXYZ6789');
    });

    test('une réponse dont pour n\'est pas un code DewDrop est refusée', () {
      expect(
        parseTwinLink({
          'de': 'arpente',
          'code': 'QRS789',
          'pour': 'QRS789',
          'etat': state,
        }),
        isNull,
      );
    });
  });

  group('cleanTwinName', () {
    test('rien de lisible → null', () {
      expect(cleanTwinName(null), isNull);
      expect(cleanTwinName(' \u200b\n '), isNull);
    });

    test('coupé à 60 caractères (pas en unités UTF-16)', () {
      final name = cleanTwinName('🌙' * 70)!;
      expect(name.runes.length, 60);
    });
  });

  group('adresses', () {
    test(
      'demande vers Agora : sa route #/twin, paramètres dans le fragment',
      () {
        final uri = twinRequestUri(
          TwinApp.agora,
          code: 'WXYZ6789',
          name: 'Les copains',
          state: state,
        );
        expect(
          uri.toString(),
          startsWith('https://agora.heianenterprise.com/#/twin?'),
        );
        expect(uri.query, isEmpty);
        final params = Uri.splitQueryString(uri.fragment.split('?').last);
        expect(params, {
          'de': 'dewdrop',
          'code': 'WXYZ6789',
          'nom': 'Les copains',
          'etat': state,
        });
      },
    );

    test(
      'réponse vers Arpente : jumeler.html, paramètres dans le fragment',
      () {
        final uri = twinResponseUri(
          TwinApp.arpente,
          code: 'WXYZ6789',
          forCode: 'QRS789',
          state: state,
        );
        expect(uri.host, 'arpente.heianenterprise.com');
        expect(uri.path, '/jumeler.html');
        expect(uri.query, isEmpty);
        expect(Uri.splitQueryString(uri.fragment), {
          'de': 'dewdrop',
          'code': 'WXYZ6789',
          'pour': 'QRS789',
          'etat': state,
        });
      },
    );

    test('rejoindre le jumeau : adresse reconstruite depuis la base fixe', () {
      expect(
        TwinApp.agora.joinUri('ABCD2345').toString(),
        'https://agora.heianenterprise.com/#/join/ABCD2345',
      );
      expect(
        TwinApp.arpente.joinUri('QRS789').toString(),
        'https://arpente.heianenterprise.com/rejoindre.html#code=QRS789',
      );
    });
  });

  test('newTwinState : 16 octets en base64 URL, 22 caractères', () {
    final token = newTwinState(Random(1));
    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect(newTwinState(), isNot(newTwinState()));
  });

  group('matchTwinRequest', () {
    final sentAt = DateTime.utc(2026, 10, 6, 12);
    final requests = {
      state: TwinRequestSent(
        app: TwinApp.agora,
        groupId: 'g1',
        code: 'WXYZ6789',
        sentAt: sentAt,
      ),
    };
    TwinResponse response({
      TwinApp app = TwinApp.agora,
      String forCode = 'WXYZ6789',
    }) => TwinResponse(
      app: app,
      remoteCode: 'ABCD2345',
      state: state,
      forCode: forCode,
    );

    test('même jeton, même app, même code, moins de 24 h → la demande', () {
      final match = matchTwinRequest(
        requests,
        response(),
        sentAt.add(const Duration(hours: 23)),
      );
      expect(match?.groupId, 'g1');
    });

    test('une autre app, un autre code ou un jeton inconnu → rien', () {
      final now = sentAt.add(const Duration(minutes: 5));
      expect(
        matchTwinRequest(
          requests,
          response(app: TwinApp.arpente, forCode: 'WXYZ6789'),
          now,
        ),
        isNull,
      );
      expect(
        matchTwinRequest(requests, response(forCode: 'WXYZ6788'), now),
        isNull,
      );
      expect(matchTwinRequest(const {}, response(), now), isNull);
    });

    test('au-delà de 24 h, la demande ne vaut plus', () {
      expect(
        matchTwinRequest(
          requests,
          response(),
          sentAt.add(const Duration(hours: 25)),
        ),
        isNull,
      );
    });

    test('une demande se garde en JSON et se relit à l\'identique', () {
      final sent = requests[state]!;
      final back = TwinRequestSent.fromJson(sent.toJson());
      expect(back?.app, sent.app);
      expect(back?.groupId, sent.groupId);
      expect(back?.code, sent.code);
      expect(back?.sentAt, sent.sentAt);
      expect(TwinRequestSent.fromJson({'app': 'deckhand'}), isNull);
    });
  });
}
