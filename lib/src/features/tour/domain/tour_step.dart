/// The script of the home-screen tour: what each cloud bubble says and which
/// bit of the real screen it points at.
///
/// Kept as pure data (no Flutter import) so the script can be read, reordered
/// and unit-tested without pumping a widget. The presentation layer resolves
/// [TourAnchor] to an on-screen rectangle at paint time — the script itself
/// knows nothing about pixels.
///
/// Why a tour at all: DewDrop's home is almost entirely gestural (swipe up to
/// send, down to read, sideways to change world) and gestures leave no trace on
/// screen. The one-line hint that used to flash on first launch said too much
/// at once and vanished before it could be read.
library;

/// The element of the home screen a step points at. [none] means the step is
/// about the screen as a whole (the decor, the app's purpose) — no spotlight,
/// the bubble sits centred.
enum TourAnchor { none, sendHandle, receivedHandle, menuButton }

/// A gesture a step invites the user to actually perform.
///
/// The tour never blocks these: reading "glisse vers le haut" teaches far less
/// than doing it once, so the overlay lets the swipe through to the real home
/// and the step completes itself when the gesture lands.
enum TourGesture { swipeUp, swipeDown, swipeSide }

/// One bubble of the tour.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.anchor = TourAnchor.none,
    this.gesture,
  });

  final String title;
  final String body;
  final TourAnchor anchor;

  /// The gesture that satisfies this step, if any. When the user performs it,
  /// the step advances on its own after a beat — long enough to see what the
  /// gesture did.
  final TourGesture? gesture;
}

/// The home tour, in order.
///
/// Ordered by what a newcomer needs first: what the app is for, then the two
/// gestures that carry it (send / receive), then the decors, then the menu as
/// the reassuring fallback for anyone who'd rather not learn gestures at all.
/// Keep it at five — past that it stops being read.
const List<TourStep> kHomeTour = [
  TourStep(
    title: 'Une pensée, rien de plus',
    body:
        'DewDrop sert à une seule chose : dire à quelqu’un que tu penses à '
        'lui. Pas de message à écrire, pas de fil à faire défiler.',
  ),
  TourStep(
    title: 'Glisse vers le haut',
    body:
        'Essaie : ton cercle apparaît en bas. Un appui sur un visage envoie la '
        'pensée, tout de suite. Re-glisse vers le haut pour voir tout le monde.',
    anchor: TourAnchor.sendHandle,
    gesture: TourGesture.swipeUp,
  ),
  TourStep(
    title: 'Glisse vers le bas',
    body:
        'À toi : tu retrouves les pensées qu’on t’a envoyées. Quand il en '
        'arrive une, le décor s’illumine tout seul.',
    anchor: TourAnchor.receivedHandle,
    gesture: TourGesture.swipeDown,
  ),
  TourStep(
    title: 'Glisse sur les côtés',
    body:
        'Vas-y : tu passes d’un univers à l’autre parmi tes favoris ⭐. Touche '
        'le décor pour le faire réagir, et écoute — chacun a son ambiance.',
    gesture: TourGesture.swipeSide,
  ),
  TourStep(
    title: 'Et tout est aussi ici',
    body:
        'Amis, univers, réglages : le menu reprend chaque geste, au cas où. '
        'Tu peux revoir ce tuto depuis les réglages.',
    anchor: TourAnchor.menuButton,
  ),
];
