package com.housetully.dotmatrix

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dot_matrix/video",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPictureInPicture" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val aspectRatioX = call.argument<Int>("aspectRatioX") ?: 16
                    val aspectRatioY = call.argument<Int>("aspectRatioY") ?: 9
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(
                            Rational(
                                aspectRatioX.coerceAtLeast(1),
                                aspectRatioY.coerceAtLeast(1),
                            ),
                        )
                        .build()

                    result.success(enterPictureInPictureMode(params))
                }

                else -> result.notImplemented()
            }
        }
    }
}
