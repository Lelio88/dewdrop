package app.dewdrop

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine and owns DewDrop's **app-level audio focus**.
 *
 * Why this exists: `audioplayers` requests audio focus *per player*, and the
 * soundscape runs six of them (ambiance, music, four one-shots) — each grab stole
 * focus from the others, so only the last sound to start was audible. The fix was
 * `AndroidAudioFocus.none` on the global AudioContext (see `lib/main.dart`), which
 * lets the six mix… but also means DewDrop never told the system it was playing,
 * so Spotify/YouTube kept going on top of the ambiance.
 *
 * So focus is requested **once, here, for the whole app**, independently of the
 * players. Keep both halves of that contract: this class holds the focus, and the
 * players must stay on `AndroidAudioFocus.none`, or the old stealing bug returns.
 *
 * Invariants:
 * - Focus is held only while DewDrop actually plays. Dart calls `abandon` on
 *   master-mute, on background and on teardown, so the user's music resumes.
 * - Losing focus (incoming call, another media app) pushes `onFocusLost` to Dart,
 *   which pauses the players **without** abandoning — otherwise the listener is
 *   dropped and the `onFocusGained` that ends a transient loss never arrives.
 * - Ducking is not handled here: `willPauseWhenDucked` defaults to false, so the
 *   system lowers our volume itself and no callback is delivered.
 *
 * Dart side: `lib/src/features/ambient/application/audio_focus.dart`.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "app.dewdrop/audio_focus"
    }

    private var channel: MethodChannel? = null
    private var focusRequest: AudioFocusRequest? = null
    private var holdsFocus = false

    private val audioManager: AudioManager by lazy {
        applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                holdsFocus = true
                channel?.invokeMethod("onFocusGained", null)
            }
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                holdsFocus = false
                channel?.invokeMethod("onFocusLost", null)
            }
            else -> Unit // CAN_DUCK — the system ducks us, nothing to do.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "request" -> result.success(requestFocus())
                    "abandon" -> {
                        abandonFocus()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        abandonFocus()
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    /** Requests app-wide focus. Returns false when the system denied it (a call
     *  is in progress); Dart plays anyway — a silent ambiance would be worse. */
    private fun requestFocus(): Boolean {
        if (holdsFocus) return true
        val outcome = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: buildFocusRequest().also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        holdsFocus = outcome == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return holdsFocus
    }

    private fun abandonFocus() {
        if (!holdsFocus && focusRequest == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        holdsFocus = false
    }

    private fun buildFocusRequest(): AudioFocusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setOnAudioFocusChangeListener(focusListener)
            .build()
}
