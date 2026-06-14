import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/profile/data/profile_repository.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

/// The signed-in user's profile (null when signed out / not yet created).
/// Invalidate this after editing the profile to refresh.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateChangesProvider); // re-fetch on sign in/out
  return ref.watch(profileRepositoryProvider).getMyProfile();
});
