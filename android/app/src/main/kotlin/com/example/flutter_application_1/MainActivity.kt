package com.example.flutter_application_1

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    val albumName = call.argument<String>("albumName") ?: "SidmaxGeotag"
                    val fileName = call.argument<String>("fileName") ?: "SidmaxGeotag_${System.currentTimeMillis()}.jpg"

                    if (filePath == null) {
                        result.error("INVALID_PATH", "File path cannot be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val savedUri = saveImage(File(filePath), albumName, fileName)
                        if (savedUri != null) {
                            result.success(savedUri.toString())
                        } else {
                            result.error("SAVE_FAILED", "Failed to save image to gallery", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.localizedMessage, null)
                    }
                }
                "openGoogleMaps" -> {
                    val lat = call.argument<Double>("latitude") ?: 0.0
                    val lng = call.argument<Double>("longitude") ?: 0.0
                    val mode = call.argument<String>("mode") ?: "liveView"

                    try {
                        val uri = when (mode) {
                            "streetView" -> Uri.parse("google.streetview:cbll=$lat,$lng")
                            "navigation" -> Uri.parse("google.navigation:q=$lat,$lng")
                            else -> Uri.parse("geo:$lat,$lng?q=$lat,$lng(Live+Location)&z=19")
                        }
                        val mapIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                            setPackage("com.google.android.apps.maps")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        if (mapIntent.resolveActivity(packageManager) != null) {
                            startActivity(mapIntent)
                            result.success(true)
                        } else {
                            val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                            val webIntent = Intent(Intent.ACTION_VIEW, webUri).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(webIntent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                            val webIntent = Intent(Intent.ACTION_VIEW, webUri).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(webIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("MAPS_FAILED", e2.localizedMessage, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveImage(sourceFile: File, albumName: String, fileName: String): Uri? {
        if (!sourceFile.exists()) return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$albumName")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues) ?: return null

            resolver.openOutputStream(uri)?.use { outStream ->
                FileInputStream(sourceFile).use { inStream ->
                    inStream.copyTo(outStream)
                }
            }

            contentValues.clear()
            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            uri
        } else {
            @Suppress("DEPRECATION")
            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val albumDir = File(picturesDir, albumName)
            if (!albumDir.exists()) {
                albumDir.mkdirs()
            }
            val destFile = File(albumDir, fileName)
            FileInputStream(sourceFile).use { inStream ->
                FileOutputStream(destFile).use { outStream ->
                    inStream.copyTo(outStream)
                }
            }
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(destFile.absolutePath),
                arrayOf("image/jpeg"),
                null
            )
            Uri.fromFile(destFile)
        }
    }
}
