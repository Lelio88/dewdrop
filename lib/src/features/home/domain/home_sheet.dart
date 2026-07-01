/// The home's two gesture sheets and their two reveal stages, plus the pure
/// transition a vertical fling applies to them.
///
/// The home has two invisible pull sheets: swipe ↑ reveals "envoyer", swipe ↓
/// reveals "pensées reçues". Each opens at a compact [SheetStage.peek] and a
/// *second* fling in the same direction escalates it to [SheetStage.full] (the
/// whole list, in place). A fling in the opposite direction retreats one level
/// (full → peek → closed).
///
/// The transition is kept here as a pure function so the state machine can be
/// unit-tested without pumping the whole [HomeView] (which needs Supabase,
/// sound, push… providers). The widget owns only the animation + rendering.
///
/// Invariant: [SheetStage] is only meaningful while [HomeSheet] is not
/// [HomeSheet.none]; a closed sheet always resets to [SheetStage.peek].
library;

/// Which gesture sheet is revealed on the home.
enum HomeSheet { none, send, recus }

/// How far the open sheet is revealed.
enum SheetStage { peek, full }

/// An immutable snapshot of the home's sheet state.
class SheetState {
  const SheetState(this.sheet, this.stage);

  /// The closed, reset state.
  static const closed = SheetState(HomeSheet.none, SheetStage.peek);

  final HomeSheet sheet;
  final SheetStage stage;

  bool get isOpen => sheet != HomeSheet.none;

  @override
  bool operator ==(Object other) =>
      other is SheetState && other.sheet == sheet && other.stage == stage;

  @override
  int get hashCode => Object.hash(sheet, stage);

  @override
  String toString() => 'SheetState(${sheet.name}, ${stage.name})';
}

/// The state a vertical fling produces. [up] is true for a swipe up (negative
/// primary velocity), false for a swipe down. The caller filters out flings
/// below the velocity threshold before calling this.
///
/// Rules:
/// - closed: up opens "envoyer", down opens "pensées reçues" (both at peek).
/// - a sheet opened by a given direction *escalates* to full when flung again
///   in that same direction, and *collapses* one level (full → peek → closed)
///   when flung the opposite way.
SheetState nextSheetState(SheetState current, {required bool up}) {
  switch (current.sheet) {
    case HomeSheet.none:
      return up
          ? const SheetState(HomeSheet.send, SheetStage.peek)
          : const SheetState(HomeSheet.recus, SheetStage.peek);
    case HomeSheet.send:
      // Opened by a swipe up: further up escalates, down collapses.
      if (up) return const SheetState(HomeSheet.send, SheetStage.full);
      return current.stage == SheetStage.full
          ? const SheetState(HomeSheet.send, SheetStage.peek)
          : SheetState.closed;
    case HomeSheet.recus:
      // Opened by a swipe down: further down escalates, up collapses.
      if (!up) return const SheetState(HomeSheet.recus, SheetStage.full);
      return current.stage == SheetStage.full
          ? const SheetState(HomeSheet.recus, SheetStage.peek)
          : SheetState.closed;
  }
}
