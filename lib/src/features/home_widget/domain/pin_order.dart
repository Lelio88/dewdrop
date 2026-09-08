/// Reordering rule for the home-widget pinned list: move one entry to the
/// position the drag asked for, leaving every other entry in place.
///
/// Pure and type-agnostic so the drag logic can be tested without a widget
/// tree — the screen passes the friend ids it is about to persist.
///
/// Non-obvious choices:
/// - `newIndex` follows the `onReorderItem` convention: it is the destination
///   index **in the list once the dragged item has been removed**. Flutter
///   subtracts one for a downward move before invoking the callback, so this
///   function must NOT adjust it again — the deprecated `onReorder` did hand
///   over an unadjusted index, and the `if (newIndex > oldIndex) newIndex -= 1`
///   dance that used to live at the call site belongs to that older contract.
/// - Returns a new list rather than reordering in place: the caller holds the
///   items it is rendering, and mutating them under the build would reorder the
///   list before the save round-trip confirms it.
///
/// Example:
/// ```dart
/// onReorderItem: (oldIndex, newIndex) => _savePinned(
///   reorderPinned([for (final f in pinned) f.profile.id], oldIndex, newIndex),
/// ),
/// ```
List<T> reorderPinned<T>(List<T> items, int oldIndex, int newIndex) {
  final out = [...items];
  out.insert(newIndex, out.removeAt(oldIndex));
  return out;
}
