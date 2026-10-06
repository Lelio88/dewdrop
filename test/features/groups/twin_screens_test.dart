import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/application/twin_providers.dart';
import 'package:dewdrop/src/features/groups/domain/twin_repository.dart';
import 'package:dewdrop/src/features/groups/presentation/join_circle_screen.dart';
import 'package:dewdrop/src/features/groups/presentation/twin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

/// Les deux écrans ouverts par un lien d'Agora ou d'Arpente : ce qu'ils
/// montrent d'un lien invalide ou étranger, et le parcours d'une demande.

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

void main() {
  late FakeTwinRepository twins;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..session = _session,
          ),
          twinRepositoryProvider.overrideWithValue(twins),
          groupRepositoryProvider.overrideWithValue(FakeGroupRepository()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(theme: ThemeData.dark(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => twins = FakeTwinRepository());

  testWidgets('un lien de jumelage mal formé n\'ouvre qu\'un message', (
    tester,
  ) async {
    await pump(
      tester,
      const TwinScreen(params: {'de': 'evil', 'code': 'ABCD2345'}),
    );
    expect(find.text('Ce lien de jumelage n\'est pas valide.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('une réponse qui ne répond à rien d\'ici ne relie rien', (
    tester,
  ) async {
    await pump(
      tester,
      const TwinScreen(
        params: {
          'de': 'agora',
          'code': 'ABCD2345',
          'pour': 'WXYZ2222',
          'etat': 'un-jeton-jamais-envoye',
        },
      ),
    );
    expect(
      find.textContaining(
        'ne répond à aucun jumelage lancé depuis ce téléphone',
      ),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('un code d\'un lien : aperçu du cercle, puis demande envoyée', (
    tester,
  ) async {
    twins.previews['WXYZ2222'] = const JoinCodePreview(
      groupId: 'g1',
      name: 'Les copains',
      creatorHandle: 'cleo',
      isMember: false,
      alreadyRequested: false,
    );
    await pump(tester, const JoinCircleScreen(initialCode: 'wxyz2222'));

    expect(find.text('« Les copains », le cercle de @cleo'), findsOneWidget);
    await tester.tap(find.text('Demander à rejoindre'));
    await tester.pumpAndSettle();

    expect(twins.requestedCodes, ['WXYZ2222']);
    expect(find.text('Demande envoyée ✨'), findsOneWidget);
    expect(find.textContaining('@cleo aura accepté'), findsOneWidget);
  });

  testWidgets('un code inconnu dit seulement qu\'aucun cercle ne correspond', (
    tester,
  ) async {
    await pump(tester, const JoinCircleScreen(initialCode: 'ZZZZ2222'));
    expect(find.textContaining('Aucun cercle ne correspond'), findsOneWidget);
    expect(find.text('Demander à rejoindre'), findsNothing);
  });

  testWidgets('un code mal formé est refusé sans interroger le serveur', (
    tester,
  ) async {
    await pump(tester, const JoinCircleScreen());
    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.tap(find.text('Voir le cercle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('8 caractères'), findsOneWidget);
    expect(twins.previewedCodes, isEmpty);
    expect(twins.requestedCodes, isEmpty);
  });
}
