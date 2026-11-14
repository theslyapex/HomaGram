import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey homagramScreenCaptureKey = GlobalKey();

class BugReportPreferences {
  BugReportPreferences._();

  static final ValueNotifier<bool> shakeEnabled = ValueNotifier<bool>(false);
  static const String _preferenceKey = 'homagram_shake_bug_report_enabled';

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    shakeEnabled.value = preferences.getBool(_preferenceKey) ?? true;
  }

  static Future<void> setShakeEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, enabled);
    shakeEnabled.value = enabled;
  }

  static Future<Uint8List?> captureScreen() async {
    await WidgetsBinding.instance.endOfFrame;
    final context = homagramScreenCaptureKey.currentContext;
    final object = context?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;

    ui.Image? image;
    try {
      image = await object.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose();
    }
  }
}
