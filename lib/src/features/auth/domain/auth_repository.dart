import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication boundary. The concrete implementation wraps Supabase Auth.
///
/// Note: the session/user/auth-state types are Supabase's — auth is
/// intentionally coupled to its session model, so the interface re-exposes them
/// rather than re-mapping to bespoke domain types.
abstract interface class AuthRepository {
  Session? get currentSession;
  User? get currentUser;
  Stream<AuthState> authStateChanges();
  Future<void> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}
