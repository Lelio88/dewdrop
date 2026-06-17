import 'dart:ui';

import 'package:dewdrop/src/common/glass.dart';
import 'package:dewdrop/src/features/groups/application/group_providers.dart';
import 'package:dewdrop/src/features/groups/domain/group.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Glass sheet to send a "pensée" to a friend ([to]) OR a whole [group], with an
/// anonymity toggle. Pops `true` on success. Exactly one of [to]/[group] is set.
class SendThoughtSheet extends ConsumerStatefulWidget {
  const SendThoughtSheet({super.key, this.to, this.group})
    : assert(to != null || group != null, 'send to a friend or a group');

  final Profile? to;
  final Group? group;

  @override
  ConsumerState<SendThoughtSheet> createState() => _SendThoughtSheetState();
}

class _SendThoughtSheetState extends ConsumerState<SendThoughtSheet> {
  bool _anonymous = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _anonymous = ref.read(myProfileProvider).value?.defaultAnonymous ?? false;
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final group = widget.group;
      if (group != null) {
        await ref
            .read(groupRepositoryProvider)
            .sendToGroup(group.id, anonymous: _anonymous);
      } else {
        await ref
            .read(thoughtRepositoryProvider)
            .sendThought(widget.to!.id, anonymous: _anonymous);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Échec de l'envoi.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    final target = widget.group != null
        ? 'au groupe ${widget.group!.name}'
        : 'à ${widget.to!.displayName?.isNotEmpty == true ? widget.to!.displayName! : '@${widget.to!.handle}'}';
    final bottom = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottom),
          decoration: BoxDecoration(
            color: w.withValues(alpha: 0.10),
            border: Border.all(color: w.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: w.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.auto_awesome,
                color: w.withValues(alpha: 0.85),
                size: 30,
              ),
              const SizedBox(height: 12),
              Text(
                'Envoyer une pensée',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: w,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                target,
                textAlign: TextAlign.center,
                style: TextStyle(color: w.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    color: w.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Envoyer anonymement',
                      style: TextStyle(color: w.withValues(alpha: 0.85)),
                    ),
                  ),
                  Switch(
                    value: _anonymous,
                    onChanged: (v) => setState(() => _anonymous = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GlassButton(label: 'Envoyer 💭', loading: _sending, onTap: _send),
            ],
          ),
        ),
      ),
    );
  }
}
