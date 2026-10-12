package net.roamkit.roamkit_mobile

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.euicc.DownloadableSubscription
import android.telephony.euicc.EuiccManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "net.roamkit.mobile/euicc"
    private val callbackAction = "net.roamkit.mobile.EUICC_DOWNLOAD"
    private val downloadRequest = 70
    private val resolutionRequest = 71
    private var pendingResult: MethodChannel.Result? = null
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != callbackAction) {
                return
            }
            val manager = euiccManager()
            val code = resultCode
            if (code == EuiccManager.EMBEDDED_SUBSCRIPTION_RESULT_RESOLVABLE_ERROR &&
                manager != null
            ) {
                try {
                    manager.startResolutionActivity(
                        this@MainActivity,
                        resolutionRequest,
                        intent,
                        callbackIntent(resolutionRequest),
                    )
                } catch (_: Exception) {
                    finishInstall("Could not open the system install screen.")
                }
                return
            }
            if (code == EuiccManager.EMBEDDED_SUBSCRIPTION_RESULT_OK) {
                finishInstall(null)
                return
            }
            finishInstall("Could not install the eSIM.")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "openSetupLink") {
                    openSetupLink(call.argument<String>("url").orEmpty(), result)
                    return@setMethodCallHandler
                }
                if (call.method != "download") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val code = call.argument<String>("activationCode")?.trim().orEmpty()
                if (code.isEmpty()) {
                    result.success("Missing activation code.")
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    result.success("This phone cannot install an eSIM.")
                    return@setMethodCallHandler
                }
                val manager = euiccManager()
                if (manager == null || !manager.isEnabled) {
                    result.success("This phone cannot install an eSIM.")
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.success("Install already in progress.")
                    return@setMethodCallHandler
                }
                pendingResult = result
                try {
                    val subscription = DownloadableSubscription.forActivationCode(code)
                    manager.downloadSubscription(
                        subscription,
                        true,
                        callbackIntent(downloadRequest),
                    )
                } catch (_: Exception) {
                    finishInstall("Could not install the eSIM.")
                }
            }
    }

    override fun onStart() {
        super.onStart()
        if (receiverRegistered) {
            return
        }
        val filter = IntentFilter(callbackAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            applicationContext.unregisterReceiver(receiver)
            receiverRegistered = false
        }
        if (isFinishing) {
            finishInstall("Could not install the eSIM.")
        }
        super.onDestroy()
    }

    private fun openSetupLink(url: String, result: MethodChannel.Result) {
        if (url.isBlank()) {
            result.success("Missing activation code.")
            return
        }
        val uri = Uri.parse(url)
        val handlers = listOfNotNull(
            resolveGmsSetupActivity(uri),
            ComponentName(
                "com.google.android.gms",
                "com.google.android.gms.esim.esimsetup.EsimSetupProvisioningActivity",
            ),
        ).distinct()
        for (handler in handlers) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri).setComponent(handler))
                result.success(null)
                return
            } catch (_: ActivityNotFoundException) {
            } catch (_: Exception) {
            }
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (_: Exception) {
            result.success("Could not open Android eSIM setup.")
        }
    }

    private fun resolveGmsSetupActivity(uri: Uri): ComponentName? {
        val probe = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            setPackage("com.google.android.gms")
        }
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                probe,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            packageManager.queryIntentActivities(probe, PackageManager.MATCH_DEFAULT_ONLY)
        }
        val activity = matches.firstOrNull()?.activityInfo ?: return null
        return ComponentName(activity.packageName, activity.name)
    }

    private fun euiccManager(): EuiccManager? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return null
        }
        return getSystemService(EUICC_SERVICE) as? EuiccManager
    }

    private fun callbackIntent(requestCode: Int): PendingIntent {
        val intent = Intent(callbackAction).setPackage(packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(this, requestCode, intent, flags)
    }

    private fun finishInstall(message: String?) {
        val result = pendingResult ?: return
        pendingResult = null
        try {
            result.success(message)
        } catch (_: Exception) {
            // The Flutter engine can already be gone when the activity finishes.
        }
    }
}
