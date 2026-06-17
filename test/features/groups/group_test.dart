import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group', () {
    test('fromMap parses id / name / creator', () {
      final g = Group.fromMap({
        'id': 'g1',
        'name': 'Cercle',
        'creator_id': 'u1',
      });
      expect(g.id, 'g1');
      expect(g.name, 'Cercle');
      expect(g.creatorId, 'u1');
    });

    test('isCreator is true only for the owner', () {
      const g = Group(id: 'g1', name: 'X', creatorId: 'owner');
      expect(g.isCreator('owner'), isTrue);
      expect(g.isCreator('someone-else'), isFalse);
    });
  });
}
