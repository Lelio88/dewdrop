package app.dewdrop

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: a row of up to four friend circles. Tapping a circle fires
 * a background broadcast handled by the Dart `dewDropWidgetBackgroundCallback`,
 * which sends a pensée WITHOUT opening the app.
 *
 * Reads the slot data Flutter wrote (via WidgetSyncService) from [widgetData]:
 *   signed_in (Bool), slot_count (Int), slot{i}_id / slot{i}_initial / slot{i}_label.
 *
 * After a successful send the Dart isolate writes sent_id (String) + sent_at
 * (Long, epoch ms) and asks for a redraw; the matching slot then shows a ✓ for
 * [SENT_WINDOW_MS], and we schedule a one-shot revert so it returns to the normal
 * circle without the app being reopened. (If that alarm is ever missed, the next
 * in-app sync redraws past the window anyway — the ✓ is derived purely from
 * sent_at recency, so a stale value never shows ✓ on a fresh render.)
 *
 * These keys are a contract shared with widget_sync_service.dart and
 * widget_background.dart — change one side, change all three.
 */
class DewDropWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rootIds = intArrayOf(
            R.id.slot0_root, R.id.slot1_root, R.id.slot2_root, R.id.slot3_root,
        )
        val initialIds = intArrayOf(
            R.id.slot0_initial, R.id.slot1_initial,
            R.id.slot2_initial, R.id.slot3_initial,
        )
        val labelIds = intArrayOf(
            R.id.slot0_label, R.id.slot1_label, R.id.slot2_label, R.id.slot3_label,
        )

        val signedIn = widgetData.getBoolean("signed_in", false)
        val count = widgetData.getInt("slot_count", 0)

        // "Just sent" confirmation: show a ✓ on the matching slot for a short
        // window after the background isolate reports a successful send.
        val sentId = widgetData.getString("sent_id", null)
        val sentAt = widgetData.getString("sent_at", null)?.toLongOrNull() ?: 0L
        val sentActive = sentId != null &&
            System.currentTimeMillis() - sentAt in 0L until SENT_WINDOW_MS
        var showedSent = false

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.dewdrop_widget)

            var shown = 0
            for (i in rootIds.indices) {
                val recipientId = widgetData.getString("slot${i}_id", null)
                val visible = signedIn && i < count && !recipientId.isNullOrEmpty()
                if (visible) {
                    views.setViewVisibility(rootIds[i], View.VISIBLE)
                    if (sentActive && recipientId == sentId) {
                        views.setTextViewText(initialIds[i], "✓")
                        views.setTextViewText(
                            labelIds[i],
                            context.getString(R.string.widget_sent),
                        )
                        showedSent = true
                    } else {
                        views.setTextViewText(
                            initialIds[i],
                            widgetData.getString("slot${i}_initial", "?"),
                        )
                        views.setTextViewText(
                            labelIds[i],
                            widgetData.getString("slot${i}_label", ""),
                        )
                    }
                    val uri = Uri.parse(
                        "dewdrop://widget/send?recipientId=$recipientId",
                    )
                    views.setOnClickPendingIntent(
                        rootIds[i],
                        HomeWidgetBackgroundIntent.getBroadcast(context, uri),
                    )
                    shown++
                } else {
                    views.setViewVisibility(rootIds[i], View.GONE)
                }
            }

            val empty = !signedIn || shown == 0
            views.setViewVisibility(R.id.slots_row, if (empty) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_hint, if (empty) View.VISIBLE else View.GONE)
            // The hint opens the app (add friends / sign in).
            views.setOnClickPendingIntent(
                R.id.widget_hint,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            appWidgetManager.updateAppWidget(id, views)
        }

        // A ✓ is showing — schedule a single redraw just after the window so it
        // reverts to the normal circle even though the app stays closed. Inexact
        // alarm: no special permission needed, and a little slack is fine.
        if (showedSent) scheduleRevert(context)
    }

    private fun scheduleRevert(context: Context) {
        val ids = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, DewDropWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val intent = Intent(context, DewDropWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            REVERT_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + SENT_WINDOW_MS + 250L,
            pi,
        )
    }

    companion object {
        /** How long the ✓ confirmation stays on the tapped slot. */
        private const val SENT_WINDOW_MS = 2500L
        private const val REVERT_REQUEST_CODE = 7341
    }
}
