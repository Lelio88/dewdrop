import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  test('register saves the current token for the user', () async {
    final repo = FakePushRepository();
    addTearDown(repo.dispose);
    final svc = PushService(repo);
    addTearDown(svc.dispose);

    await svc.register('u1');

    expect(repo.saved, [('u1', 'tok-1')]);
  });

  test('register does nothing when permission is denied', () async {
    final repo = FakePushRepository()..permission = false;
    addTearDown(repo.dispose);
    final svc = PushService(repo);
    addTearDown(svc.dispose);

    await svc.register('u1');

    expect(repo.saved, isEmpty);
  });

  test('a later token refresh re-saves for the registered user', () async {
    final repo = FakePushRepository();
    addTearDown(repo.dispose);
    final svc = PushService(repo);
    addTearDown(svc.dispose);

    await svc.register('u1');
    repo.emitRefresh('tok-2');
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // let the listener fire

    expect(repo.saved, [('u1', 'tok-1'), ('u1', 'tok-2')]);
  });

  test('unregister deletes this device token', () async {
    final repo = FakePushRepository();
    addTearDown(repo.dispose);
    final svc = PushService(repo);
    addTearDown(svc.dispose);

    await svc.register('u1');
    await svc.unregister();

    expect(repo.deleted, ['tok-1']);
  });

  test('unregister is a no-op when never registered', () async {
    final repo = FakePushRepository();
    addTearDown(repo.dispose);
    final svc = PushService(repo);
    addTearDown(svc.dispose);

    await svc.unregister();

    expect(repo.deleted, isEmpty);
  });
}
