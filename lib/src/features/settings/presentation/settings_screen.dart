import 'dart:async';

import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-app settings: default anonymity + quiet hours. Persisted to the profile
/// (quiet hours will gate push notifications once FCM is wired).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _anonymous = false;
  bool _quiet = false;
  int _start = 22;
  int _end = 7;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value;
    if (p != null) {
      _anonymous = p.defaultAnonymous;
      _quiet = p.quietStart != null && p.quietEnd != null;
      _start = p.quietStart ?? 22;
      _end = p.quietEnd ?? 7;
    }
  }

  Future<void> _persist() async {
    await ref.read(profileRepositoryProvider).updateSettings(
          defaultAnonymous: _anonymous,
          quietStart: _quiet ? _start : null,
          quietEnd: _quiet ? _end : null,
        );
    ref.invalidate(myProfileProvider);
  }

  Future<void> _pickHour(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start ? _start : _end, minute: 0),
    );
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t.hour;
      } else {
        _end = t.hour;
      }
    });
    unawaited(_persist());
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Réglages'),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _section(w, 'Pensées'),
              _card(
                w,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _anonymous,
                  onChanged: (v) {
                    setState(() => _anonymous = v);
                    unawaited(_persist());
                  },
                  title: const Text('Envoyer anonymement par défaut'),
                  subtitle: Text("Tes amis verront « Quelqu'un a pensé à toi ».",
                      style: TextStyle(color: w.withValues(alpha: 0.5))),
                ),
              ),
              const SizedBox(height: 24),
              _section(w, 'Heures calmes'),
              _card(
                w,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _quiet,
                      onChanged: (v) {
                        setState(() => _quiet = v);
                        unawaited(_persist());
                      },
                      title: const Text('Ne pas déranger'),
                      subtitle: Text('Aucune notification pendant ce créneau.',
                          style: TextStyle(color: w.withValues(alpha: 0.5))),
                    ),
                    if (_quiet)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        child: Row(
                          children: [
                            Text('De', style: TextStyle(color: w.withValues(alpha: 0.7))),
                            const SizedBox(width: 10),
                            _hourChip(w, _start, () => _pickHour(true)),
                            const SizedBox(width: 14),
                            Text('à', style: TextStyle(color: w.withValues(alpha: 0.7))),
                            const SizedBox(width: 10),
                            _hourChip(w, _end, () => _pickHour(false)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(Color w, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: w.withValues(alpha: 0.6))),
      );

  Widget _card(Color w, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: w.withValues(alpha: 0.06),
          border: Border.all(color: w.withValues(alpha: 0.12)),
        ),
        child: child,
      );

  Widget _hourChip(Color w, int hour, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: w.withValues(alpha: 0.12),
            border: Border.all(color: w.withValues(alpha: 0.2)),
          ),
          child: Text('${hour.toString().padLeft(2, '0')}h',
              style: TextStyle(color: w, fontWeight: FontWeight.w600)),
        ),
      );
}
