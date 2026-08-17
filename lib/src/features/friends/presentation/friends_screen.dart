import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/friends/presentation/qr_invite.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _handle = TextEditingController();
  bool _adding = false;

  // Lookalikes offered after an exact handle missed ("tu voulais dire… ?").
  // Never populated proactively while typing: the suggestion only ever answers
  // a failed attempt, so the app stays a private circle rather than a
  // browsable directory. Cleared on the next attempt or a successful add.
  List<Profile> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    // Editing the field invalidates the suggestions it produced.
    _handle.addListener(_clearSuggestions);
  }

  @override
  void dispose() {
    _handle.removeListener(_clearSuggestions);
    _handle.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _clearSuggestions() {
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
  }

  Future<void> _add() async {
    final h = _handle.text.trim();
    if (h.isEmpty) return;
    setState(() {
      _adding = true;
      _suggestions = const [];
    });
    try {
      await ref.read(friendRepositoryProvider).sendRequest(h);
      _handle.clear();
      _snack('Demande envoyée à @${h.toLowerCase()} ✨');
    } on FriendException catch (e) {
      _snack(e.message);
      if (e.unknownHandle) await _loadSuggestions(h);
    } on Exception catch (_) {
      _snack('Une erreur est survenue.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Offer the closest handles to a typo. Best-effort — the repository swallows
  /// its own failures, so a suggestion outage leaves the plain error message
  /// (already shown) as the only feedback.
  Future<void> _loadSuggestions(String query) async {
    final list = await ref.read(friendRepositoryProvider).suggestHandles(query);
    if (!mounted) return;
    setState(() => _suggestions = list);
  }

  /// Add someone already resolved to a profile — a suggestion here, a fellow
  /// group member in [GroupScreen].
  Future<void> _addProfile(Profile p) async {
    setState(() => _adding = true);
    try {
      await ref.read(friendRepositoryProvider).sendRequestTo(p.id);
      _handle.clear();
      if (mounted) setState(() => _suggestions = const []);
      _snack('Demande envoyée à @${p.handle} ✨');
    } on FriendException catch (e) {
      _snack(e.message);
    } on Exception catch (_) {
      _snack('Une erreur est survenue.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _scan() async {
    final handle = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanQrScreen()));
    if (handle == null || !mounted) return;
    setState(() => _adding = true);
    try {
      await ref.read(friendRepositoryProvider).sendRequest(handle);
      _snack('Demande envoyée à @${handle.toLowerCase()} ✨');
    } on FriendException catch (e) {
      _snack(e.message);
    } on Exception catch (_) {
      _snack('Une erreur est survenue.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showMyQr() {
    final handle = ref.read(myProfileProvider).value?.handle;
    if (handle == null) {
      _snack('Profil indisponible.');
      return;
    }
    showMyQrSheet(context, handle);
  }

  Future<void> _accept(String id) async {
    try {
      await ref.read(friendRepositoryProvider).acceptRequest(id);
      if (!mounted) return;
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(friendsProvider);
    } on Exception catch (_) {
      _snack('Action impossible pour le moment.');
    }
  }

  Future<void> _reject(String id) async {
    try {
      await ref.read(friendRepositoryProvider).removeFriendship(id);
      if (!mounted) return;
      ref.invalidate(incomingRequestsProvider);
    } on Exception catch (_) {
      _snack('Action impossible pour le moment.');
    }
  }

  void _openGroup(Group g) => context.push('/group', extra: g);

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau groupe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Nom du groupe'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final g = await ref.read(groupRepositoryProvider).createGroup(name);
      ref.invalidate(myGroupsProvider);
      if (mounted) _openGroup(g); // jump in to add members
    } on Exception catch (_) {
      _snack('Création impossible pour le moment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    final requests = ref.watch(incomingRequestsProvider);
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Amis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scanner un QR',
            onPressed: _scan,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Mon QR code',
            onPressed: _showMyQr,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12162A), Color(0xFF06070E)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(incomingRequestsProvider);
              ref.invalidate(friendsProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlassTextField(
                          controller: _handle,
                          hint: 'Ajouter par @handle',
                          icon: Icons.person_add_alt_1,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: GlassButton(
                          label: 'Inviter',
                          loading: _adding,
                          onTap: _add,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_suggestions.isNotEmpty) _suggestionsBlock(white),
                const SizedBox(height: 24),
                _section(white, 'Demandes reçues'),
                requests.when(
                  loading: () => const _Loading(),
                  error: (_, _) => _error(white),
                  data: (list) => list.isEmpty
                      ? _empty(white, 'Aucune demande.')
                      : Column(
                          children: [
                            for (final r in list) _requestTile(white, r),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                _section(white, 'Mes amis'),
                friends.when(
                  loading: () => const _Loading(),
                  error: (_, _) => _error(white),
                  data: (list) => list.isEmpty
                      ? _empty(white, 'Pas encore d\'amis. Invite quelqu\'un !')
                      : Column(
                          children: [
                            for (final f in list) _friendTile(white, f),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _section(white, 'Mes groupes'),
                    TextButton.icon(
                      onPressed: _createGroup,
                      icon: const Icon(
                        Icons.add,
                        size: 18,
                        color: Color(0xFF8FE3A8),
                      ),
                      label: const Text(
                        'Créer',
                        style: TextStyle(color: Color(0xFF8FE3A8)),
                      ),
                    ),
                  ],
                ),
                groups.when(
                  loading: () => const _Loading(),
                  error: (_, _) => _error(white),
                  data: (list) => list.isEmpty
                      ? _empty(
                          white,
                          'Aucun groupe. Crée un cercle pour envoyer à plusieurs amis d\'un coup.',
                        )
                      : Column(
                          children: [for (final g in list) _groupTile(white, g)],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The "tu voulais dire… ?" block: the few handles closest to what was typed,
  /// each addable in one tap. Shown only after an exact handle came back empty.
  Widget _suggestionsBlock(Color w) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'Tu voulais dire…',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: w.withValues(alpha: 0.6),
            ),
          ),
        ),
        for (final p in _suggestions)
          _personTile(
            w,
            p,
            onTap: _adding ? null : () => _addProfile(p),
            trailing: Icon(
              Icons.person_add_alt_1,
              color: const Color(0xFF8FE3A8).withValues(alpha: _adding ? 0.4 : 1),
            ),
          ),
      ],
    ),
  );

  Widget _section(Color w, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: w.withValues(alpha: 0.6),
      ),
    ),
  );

  Widget _requestTile(Color w, IncomingRequest r) => _personTile(
    w,
    r.requester,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check_circle, color: Color(0xFF8FE3A8)),
          onPressed: () => _accept(r.friendshipId),
        ),
        IconButton(
          icon: Icon(Icons.cancel, color: w.withValues(alpha: 0.4)),
          onPressed: () => _reject(r.friendshipId),
        ),
      ],
    ),
  );

  Widget _friendTile(Color w, Friend f) => _personTile(
    w,
    f.profile,
    onTap: () => _friendActions(f.profile),
    trailing: Icon(Icons.more_horiz, color: w.withValues(alpha: 0.5)),
  );

  Widget _groupTile(Color w, Group g) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      onTap: () => _openGroup(g),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF8FB7FF).withValues(alpha: 0.18),
        child: Icon(Icons.group_rounded, color: w.withValues(alpha: 0.9), size: 20),
      ),
      title: Text(g.name),
      trailing: Icon(Icons.chevron_right, color: w.withValues(alpha: 0.5)),
    ),
  );

  /// Long-press a friend → block or report them.
  Future<void> _friendActions(Profile p) async {
    final name = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : '@${p.handle}';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF12162A),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFFF6B5A)),
              title: const Text(
                'Bloquer',
                style: TextStyle(color: Color(0xFFFF6B5A)),
              ),
              subtitle: Text(
                "$name ne pourra plus t'envoyer de pensée",
                style: const TextStyle(color: Colors.white54),
              ),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.white70),
              title: const Text(
                'Signaler',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(friendRepositoryProvider);
    try {
      if (action == 'block') {
        await repo.block(p.id);
      } else {
        await repo.report(p.id);
      }
      if (!mounted) return;
      if (action == 'block') {
        ref.invalidate(friendsProvider);
        _snack('$name bloqué.');
      } else {
        _snack('Signalement envoyé.');
      }
    } on Exception catch (_) {
      if (mounted) _snack('Action impossible pour le moment.');
    }
  }

  Widget _personTile(
    Color w,
    Profile p, {
    required Widget trailing,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final name = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : '@${p.handle}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: CircleAvatar(
          backgroundColor: w.withValues(alpha: 0.14),
          child: Text(_initial(p), style: TextStyle(color: w)),
        ),
        title: Text(name),
        subtitle: Text(
          '@${p.handle}',
          style: TextStyle(color: w.withValues(alpha: 0.5)),
        ),
        trailing: trailing,
      ),
    );
  }

  String _initial(Profile p) {
    final base = p.displayName?.isNotEmpty == true
        ? p.displayName!
        : (p.handle ?? '?');
    return base.isEmpty ? '?' : base[0].toUpperCase();
  }

  Widget _empty(Color w, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(msg, style: TextStyle(color: w.withValues(alpha: 0.45))),
  );

  Widget _error(Color w) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(
      'Impossible de charger pour le moment.',
      style: TextStyle(color: w.withValues(alpha: 0.6)),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    ),
  );
}
