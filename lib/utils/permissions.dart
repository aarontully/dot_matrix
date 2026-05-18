import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests a permission and shows a snackbar if denied.
/// Returns true if granted (or already granted).
Future<bool> requestPermission(
  BuildContext context, {
  required Permission permission,
  required String name,
}) async {
  final status = await permission.request();
  if (status.isGranted) return true;

  if (context.mounted) {
    Get.snackbar('Permission denied', '$name permission denied.');
  }
  return false;
}

/// Requests microphone permission for voice recording.
Future<bool> requestMicPermission(BuildContext context) =>
    requestPermission(context, permission: Permission.microphone, name: 'Microphone');

/// Requests camera permission.
Future<bool> requestCameraPermission(BuildContext context) =>
    requestPermission(context, permission: Permission.camera, name: 'Camera');

/// Requests photo library permission.
Future<bool> requestPhotosPermission(BuildContext context) =>
    requestPermission(context, permission: Permission.photos, name: 'Photos');

/// Requests storage permission (for file picker on Android).
Future<bool> requestStoragePermission(BuildContext context) =>
    requestPermission(context, permission: Permission.storage, name: 'Storage');
