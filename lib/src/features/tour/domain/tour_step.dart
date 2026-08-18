/// The scripts of the guided tours: what each cloud bubble says, which bit of
/// the real screen it points at, which gesture satisfies it, and — on the home —
/// what the screen should be showing while it is read.
///
/// Kept as pure data (no Flutter import) so a script can be read, reordered and
/// unit-tested without pumping a widget. The presentation layer resolves
/// [TourAnchor] to an on-screen rectangle at paint time; the script itself knows
/// nothing about pixels.
///
/// **Why several short tours instead of one long one.** Everything DewDrop can
/// do (sounds per world, your own thought wording, quiet hours, friends,
/// circles) would make a fourteen-bubble wall at first launch — read by nobody,
/// and forgotten before it is useful. So the home tour covers only the home, and
/// each other screen carries two bubbles of its own, shown the first time it is
/// opened: the explanation arrives when it is about to be needed.
library;

/// The tours, one per screen. Each is remembered separately (see
/// `tour_providers.dart`), so seeing one doesn't silence the others.
enum TourId { home, friends, decors, settings }

/// The element a step points at. [none] means the step is about the screen as a
/// whole — no spotlight, the bubble sits centred.
enum TourAnchor {
  none,
  // Home
  sendHandle,
  receivedHandle,
  sendSheet,
  receivedSheet,
  sendSheetHint,
  receivedSheetHint,
  menuButton,
  // Friends
  friendsAdd,
  friendsGroups,
  // Univers picker
  decorStar,
  decorSound,
  // Settings
  settingsThought,
  settingsQuiet,
}

/// A gesture a step invites the user to actually perform.
///
/// The tour never blocks these: reading "glisse vers le haut" teaches far less
/// than doing it once, so the overlay lets the swipe through to the real screen
/// and the step completes itself when the gesture lands.
enum TourGesture { swipeUp, swipeDown, swipeSide }

/// Where a step wants its bubble, when the automatic choice can't work.
///
/// [auto] puts it beside its target — below when the target sits high, above
/// otherwise. That breaks down when the target is nearly the whole screen (a
/// full-screen drawer): there is no "beside" left, and the bubble lands on the
/// very content it is describing. Such a step names the edge it wants instead.
enum TourPlacement { auto, screenTop, screenBottom }

/// What the home should be showing while a step is read.
///
/// The tour drives the scene instead of hoping the user got there: a step that
/// explains the full-screen drawer puts the drawer full-screen, whether it was
/// reached by the swipe or by tapping "Suivant". Without this, half the script
/// would be describing something that isn't on screen.
enum TourScene { closed, sendPeek, sendFull, receivedPeek, receivedFull }

/// One bubble of a tour.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.anchor = TourAnchor.none,
    this.gesture,
    this.scene = TourScene.closed,
    this.placement = TourPlacement.auto,
  });

  final String title;
  final String body;
  final TourAnchor anchor;

  /// The gesture that satisfies this step, if any. When the user performs it,
  /// the step advances on its own after a short beat — the next bubble then
  /// comments on what just happened, so the hand-off reads as one movement.
  final TourGesture? gesture;

  /// The home state this step wants on screen. Ignored by the other tours.
  final TourScene scene;

  /// Where the bubble goes when [TourPlacement.auto] would put it somewhere
  /// unhelpful. See [TourPlacement].
  final TourPlacement placement;
}

/// The home tour: the gestures, and only the gestures.
///
/// Ordered as one continuous movement — ask for a swipe, then explain what it
/// opened, then explain the second notch of the same drawer — rather than as a
/// list of features. The two drawers are taught symmetrically so the second one
/// costs almost nothing to learn.
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
        'Essaie, depuis n’importe où sur le décor : le tiroir d’envoi arrive '
        'par le bas.',
    anchor: TourAnchor.sendHandle,
    gesture: TourGesture.swipeUp,
  ),
  TourStep(
    title: 'Un appui, c’est parti',
    body:
        'Tes derniers contacts t’attendent ici. Un appui sur un visage envoie '
        'la pensée aussitôt. Re-glisse vers le haut : le tiroir s’ouvre en '
        'grand sur tout ton monde.',
    anchor: TourAnchor.sendSheet,
    gesture: TourGesture.swipeUp,
    scene: TourScene.sendPeek,
  ),
  TourStep(
    title: 'En grand, deux zones',
    body:
        'Le haut du tiroir — là où pointe le chevron — le referme d’un '
        'glissement, sans t’empêcher de toucher les visages au passage. Tout '
        'le bas fait défiler la liste.',
    // The chevron band, not the whole panel: a full-screen drawer leaves the
    // bubble nowhere to stand, and it is that band the step is about anyway.
    anchor: TourAnchor.sendSheetHint,
    scene: TourScene.sendFull,
    placement: TourPlacement.screenBottom,
  ),
  TourStep(
    title: 'Glisse vers le bas',
    body: 'L’autre tiroir, en haut cette fois : ce qu’on t’a envoyé.',
    anchor: TourAnchor.receivedHandle,
    gesture: TourGesture.swipeDown,
  ),
  TourStep(
    title: 'Quand une pensée arrive',
    body:
        'Chaque ligne, c’est quelqu’un qui a pensé à toi. Sur le moment, ton '
        'décor s’illumine tout seul — et chaque univers a sa façon de le '
        'faire. Ici aussi, re-glisse pour ouvrir en grand.',
    anchor: TourAnchor.receivedSheet,
    gesture: TourGesture.swipeDown,
    scene: TourScene.receivedPeek,
  ),
  TourStep(
    title: 'Glisse sur les côtés',
    body:
        'Tu changes d’univers sans quitter l’accueil, et l’ambiance sonore '
        'suit. Mets une ⭐ sur tes préférés : le geste ne parcourra plus '
        'qu’eux.',
    gesture: TourGesture.swipeSide,
  ),
  TourStep(
    title: 'Et tout le reste est ici',
    body:
        'Amis, univers, réglages. Chaque écran t’expliquera ses propres '
        'possibilités la première fois que tu l’ouvriras — et tu peux revoir '
        'ce tuto quand tu veux depuis les Réglages.',
    anchor: TourAnchor.menuButton,
  ),
];

/// Friends screen — shown the first time it is opened.
const List<TourStep> kFriendsTour = [
  TourStep(
    title: 'Ajoute quelqu’un',
    body:
        'Par son @handle. S’il te manque une lettre, DewDrop te proposera les '
        'pseudos les plus proches. Les deux icônes en haut font la même chose '
        'sans rien taper : montrer ton QR, ou scanner celui d’en face.',
    anchor: TourAnchor.friendsAdd,
  ),
  TourStep(
    title: 'Les cercles',
    body:
        'Un cercle réunit plusieurs amis : une seule pensée les touche tous. '
        'Et dans un cercle, tu peux demander en ami quelqu’un que tu n’as pas '
        'encore ajouté.',
    anchor: TourAnchor.friendsGroups,
  ),
];

/// Univers picker — shown the first time it is opened.
const List<TourStep> kDecorsTour = [
  TourStep(
    title: 'L’étoile compte',
    body:
        'Les univers étoilés sont ceux que le glissement latéral fait défiler '
        'sur l’accueil. Sans aucune étoile, le geste les parcourt tous.',
    anchor: TourAnchor.decorStar,
  ),
  TourStep(
    title: 'Chaque son se règle',
    body:
        'Ambiance, musique et petits bruits : tu peux les écouter, les doser '
        'ou les couper un par un — et ces réglages valent pour cet univers '
        'seulement.',
    anchor: TourAnchor.decorSound,
  ),
];

/// Settings — shown the first time it is opened.
const List<TourStep> kSettingsTour = [
  TourStep(
    title: 'Ta signature',
    body:
        'L’emoji et la phrase que tes amis voient quand tu penses à eux se '
        'choisissent ici. Tu peux en garder plusieurs et changer d’humeur.',
    anchor: TourAnchor.settingsThought,
  ),
  TourStep(
    title: 'Heures calmes',
    body:
        'Sur la plage horaire que tu choisis, les pensées arrivent sans bruit '
        'ni vibration. Elles ne sont pas bloquées — juste silencieuses.',
    anchor: TourAnchor.settingsQuiet,
  ),
];

/// The script of a given tour.
List<TourStep> stepsFor(TourId id) => switch (id) {
  TourId.home => kHomeTour,
  TourId.friends => kFriendsTour,
  TourId.decors => kDecorsTour,
  TourId.settings => kSettingsTour,
};
