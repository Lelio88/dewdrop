import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/groups/domain/twin.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

/// Le jumelage vu de l'appareil : lancer, répondre, compléter — et la règle 4
/// du protocole (une réponse ne vaut que pour une demande partie d'ici, depuis
/// moins de 24 h, même après qu'Android a fermé l'app).

final _session = Session(
  accessToken: 'test',
  tokenType: 'bearer',
  user: User(
    id: 'me',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
  ),
);

const _circle = Group(id: 'g1', name: 'Les copains', creatorId: 'me');

void main() {
  late FakeTwinRepository twins;
  late FakeGroupRepository groups;
  late SharedPreferences prefs;
  late DateTime now;
  var tokens = 0;

  ProviderContainer container({bool signedIn = true}) {
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()..session = signedIn ? _session : null,
        ),
        twinRepositoryProvider.overrideWithValue(twins),
        groupRepositoryProvider.overrideWithValue(groups),
        sharedPreferencesProvider.overrideWithValue(prefs),
        twinClockProvider.overrideWithValue(() => now),
        twinStateGeneratorProvider.overrideWithValue(
          () => 'jeton-de-test-${++tokens}'.padRight(22, 'x'),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    twins = FakeTwinRepository();
    groups = FakeGroupRepository();
    now = DateTime.utc(2026, 10, 6, 12);
  });

  TwinResponse answerTo(Uri request, {String remote = 'ABCD2345'}) {
    final params = Uri.splitQueryString(request.fragment.split('?').last);
    return TwinResponse(
      app: TwinApp.agora,
      remoteCode: remote,
      state: params['etat']!,
      forCode: params['code']!,
    );
  }

  test(
    'lancer jumelle le cercle et ouvre la demande, nom et code compris',
    () async {
      final c = container();
      final uri = await c
          .read(twinServiceProvider)
          .start(_circle, TwinApp.agora);

      expect(twins.twinCalls.single, ('g1', TwinApp.agora, null));
      final params = Uri.splitQueryString(uri.fragment.split('?').last);
      expect(params['de'], 'dewdrop');
      expect(params['code'], twins.codeFor('g1', TwinApp.agora));
      expect(params['nom'], 'Les copains');
    },
  );

  test(
    'la réponse à une demande partie d\'ici complète le jumeau, une fois',
    () async {
      final c = container();
      final service = c.read(twinServiceProvider);
      final response = answerTo(await service.start(_circle, TwinApp.agora));

      expect(service.groupFor(response), 'g1');
      expect(await service.complete(response), 'g1');
      expect(twins.twinCalls.last, ('g1', TwinApp.agora, 'ABCD2345'));

      // La demande est consommée : rejouer la réponse ne relie plus rien.
      expect(service.groupFor(response), isNull);
      await expectLater(
        service.complete(response),
        throwsA(isA<TwinException>()),
      );
    },
  );

  test('la demande survit à la fermeture de l\'app (stockage local)', () async {
    final request = await container()
        .read(twinServiceProvider)
        .start(_circle, TwinApp.agora);
    // Un nouveau conteneur sur les mêmes préférences : l'app relancée.
    final relaunched = container().read(twinServiceProvider);
    expect(relaunched.groupFor(answerTo(request)), 'g1');
  });

  test('une réponse forgée (autre jeton ou autre code) est refusée', () async {
    final c = container();
    final service = c.read(twinServiceProvider);
    final real = answerTo(await service.start(_circle, TwinApp.agora));

    final otherState = TwinResponse(
      app: real.app,
      remoteCode: real.remoteCode,
      state: 'un-autre-jeton-forge-xx',
      forCode: real.forCode,
    );
    final otherCode = TwinResponse(
      app: real.app,
      remoteCode: real.remoteCode,
      state: real.state,
      forCode: 'WXYZ9999',
    );
    for (final forged in [otherState, otherCode]) {
      expect(service.groupFor(forged), isNull);
      await expectLater(
        service.complete(forged),
        throwsA(isA<TwinException>()),
      );
    }
    expect(twins.twinCalls, hasLength(1), reason: 'rien n\'a été complété');
  });

  test('au-delà de 24 h, la réponse ne vaut plus', () async {
    final c = container();
    final service = c.read(twinServiceProvider);
    final response = answerTo(await service.start(_circle, TwinApp.agora));
    now = now.add(const Duration(hours: 25));
    expect(service.groupFor(response), isNull);
  });

  test('accepter une demande crée le cercle nommé comme le jumeau', () async {
    final c = container();
    const request = TwinRequest(
      app: TwinApp.arpente,
      remoteCode: 'QRS789',
      state: 'jeton-de-l-autre-app-123',
      name: 'Sortie Troyes',
    );
    final answer = await c
        .read(twinServiceProvider)
        .accept(request, groupId: null, newGroupName: 'Sortie Troyes');

    expect(groups.groups.single.name, 'Sortie Troyes');
    expect(answer.groupId, groups.groups.single.id);
    expect(twins.twinCalls.single, (answer.groupId, TwinApp.arpente, 'QRS789'));
    expect(answer.response.host, 'arpente.heianenterprise.com');
    expect(Uri.splitQueryString(answer.response.fragment), {
      'de': 'dewdrop',
      'code': twins.codeFor(answer.groupId, TwinApp.arpente),
      'pour': 'QRS789',
      'etat': 'jeton-de-l-autre-app-123',
    });
  });

  test('accepter sur un cercle existant ne crée rien', () async {
    final c = container();
    const request = TwinRequest(
      app: TwinApp.agora,
      remoteCode: 'ABCD2345',
      state: 'jeton-de-l-autre-app-123',
    );
    final answer = await c
        .read(twinServiceProvider)
        .accept(request, groupId: 'g1', newGroupName: '');
    expect(groups.groups, isEmpty);
    expect(answer.groupId, 'g1');
  });

  group('demandes en attente', () {
    final requester = Profile.fromMap({'id': 'u2', 'handle': 'ines'});

    test('rien à lire (ni requête) sans session', () async {
      final c = container(signedIn: false);
      expect(await c.read(pendingJoinRequestsProvider.future), isEmpty);
      expect(twins.pendingCalls, 0);
    });

    test('la liste se relit à chaque événement temps réel', () async {
      final c = container();
      final sub = c.listen(pendingJoinRequestsProvider, (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(twins.pendingCalls, 1);

      twins.requests = [
        JoinRequest(groupId: 'g1', requester: requester, createdAt: now),
      ];
      twins.emitChange();
      await pumpEventQueue();

      expect(twins.pendingCalls, 2);
      expect(c.read(pendingJoinRequestsProvider).value, hasLength(1));
    });

    test('joinRequestsForGroupProvider ne garde que ce cercle', () async {
      twins.requests = [
        JoinRequest(groupId: 'g1', requester: requester, createdAt: now),
        JoinRequest(groupId: 'g2', requester: requester, createdAt: now),
      ];
      final c = container();
      await c.read(pendingJoinRequestsProvider.future);
      expect(
        c.read(joinRequestsForGroupProvider('g1')).value?.map((r) => r.groupId),
        ['g1'],
      );
    });
  });
}
