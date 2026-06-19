import 'package:dewdrop/src/common/deep_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR-based friend invites. The QR encodes the same HTTPS invite link as the
/// « Copier mon lien » button ([DeepLinks.invite]) — so it's scannable by any
/// camera (it opens our landing page → install/open) as well as in-app. In-app,
/// [parseInvite] pulls the bare @handle back out of whatever was scanned.
String encodeInvite(String handle) => DeepLinks.invite(handle);

/// Lenient parse of a scanned value → the bare handle (or null). Accepts the
/// HTTPS invite link, the `dewdrop://invite` / legacy `dewdrop:<handle>` forms,
/// and a raw handle with or without a leading '@'.
String? parseInvite(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  // Structured forms first: HTTPS web link or dewdrop://invite.
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final h = DeepLinks.inviteHandle(uri);
    if (h != null) return h;
  }
  // Fallback: a bare handle, optionally 'dewdrop:'-prefixed and/or '@'-prefixed.
  const legacyPrefix = 'dewdrop:';
  final body = trimmed.startsWith(legacyPrefix)
      ? trimmed.substring(legacyPrefix.length)
      : trimmed;
  final h = body.replaceAll('@', '').trim();
  return h.isEmpty ? null : h;
}

/// Bottom sheet showing the user's own QR invite for a friend to scan.
void showMyQrSheet(BuildContext context, String handle) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF12162A),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mon QR code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Fais-le scanner pour qu'on t'ajoute",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: encodeInvite(handle), size: 220),
            ),
            const SizedBox(height: 16),
            Text(
              '@$handle',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            // Un lien partageable (SMS, messagerie) cliquable partout : il ouvre
            // une page proposant « Ouvrir dans DewDrop » ou « Installer ».
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: DeepLinks.invite(handle)),
                );
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text("Lien d'invitation copié ✨")),
                  );
                }
              },
              icon: const Icon(Icons.link_rounded, color: Colors.white70),
              label: const Text(
                'Copier mon lien d\'invitation',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Full-screen camera scanner. Pops with the scanned handle (or null).
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final b in capture.barcodes) {
      final handle = parseInvite(b.rawValue);
      if (handle != null) {
        _handled = true;
        Navigator.of(context).pop(handle);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scanner un QR'),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }
}
