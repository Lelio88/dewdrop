import 'package:dewdrop/src/features/home_widget/domain/widget_gateway.dart';
import 'package:home_widget/home_widget.dart';

/// Android widget provider class (simple name). The `home_widget` plugin
/// resolves it as `<packageName>.<androidName>`, so it must match the Kotlin
/// class `app.dewdrop.DewDropWidgetProvider`.
const String kAndroidWidgetProvider = 'DewDropWidgetProvider';

/// iOS WidgetKit widget name (wired in a later phase; harmless on Android).
const String kIosWidgetName = 'DewDropWidget';

/// `home_widget`-backed implementation of [WidgetGateway].
///
/// Both the live app and the background send isolate use the same plugin
/// SharedPreferences store, so a value written here is visible to the native
/// `onUpdate` and to the `@pragma('vm:entry-point')` callback alike.
class HomeWidgetGateway implements WidgetGateway {
  const HomeWidgetGateway();

  @override
  Future<void> saveString(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  @override
  Future<void> saveInt(String key, int value) =>
      HomeWidget.saveWidgetData<int>(key, value);

  @override
  Future<void> saveBool(String key, bool value) =>
      HomeWidget.saveWidgetData<bool>(key, value);

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async =>
      await HomeWidget.getWidgetData<bool>(key, defaultValue: defaultValue) ??
      defaultValue;

  @override
  Future<void> refresh() =>
      HomeWidget.updateWidget(androidName: kAndroidWidgetProvider);
}
