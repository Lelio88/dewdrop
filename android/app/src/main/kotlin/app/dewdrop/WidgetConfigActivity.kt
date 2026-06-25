package app.dewdrop

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Reconfigure trampoline for the home-screen widget.
 *
 * Declared as the widget's `android:configure` activity, with the widget marked
 * `reconfigurable|configuration_optional`. On Android 12+ launchers that expose
 * it, long-pressing the widget → "Reconfigure" starts this activity;
 * `configuration_optional` means it is NOT shown on first placement (the widget
 * works immediately in 'auto' mode). On older Android it runs once on placement.
 *
 * It owns no UI: it confirms the widget (RESULT_OK so placement isn't cancelled),
 * then bounces into the Flutter app on the widget settings screen via the
 * home_widget launch URI `dewdrop://widget/configure` (handled in app.dart), and
 * finishes. A translucent theme keeps it invisible.
 */
class WidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )

        HomeWidgetLaunchIntent.getActivity(
            this,
            MainActivity::class.java,
            Uri.parse("dewdrop://widget/configure"),
        ).send()

        finish()
    }
}
