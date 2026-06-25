/// Port over the platform home-screen widget.
///
/// What it does: lets the app push key/value data to the native widget and ask
/// it to redraw, without the application layer touching the `home_widget`
/// plugin directly (so the sync service is unit-testable with a fake).
///
/// Invariant: keys written here are the contract the native `DewDropWidgetProvider`
/// reads back (`signed_in`, `anonymous`, `slot_count`, `slot{i}_id`,
/// `slot{i}_initial`, `slot{i}_label`). Change one side → change both.
abstract interface class WidgetGateway {
  Future<void> saveString(String key, String value);

  Future<void> saveInt(String key, int value);

  Future<void> saveBool(String key, bool value);

  /// Read a previously saved bool (used by the background send isolate).
  Future<bool> getBool(String key, {bool defaultValue = false});

  /// Tell the native widget to rebuild from the saved data.
  Future<void> refresh();
}
