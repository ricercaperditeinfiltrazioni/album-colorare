import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutosaveService {
  static const String _hasAutosaveKey = 'has_autosave';
  static const String _autosaveFilename = 'autosave_drawing.png';

  static Future<String> get _autosavePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_autosaveFilename';
  }

  static Future<void> saveDrawing(Uint8List imageBytes) async {
    try {
      final path = await _autosavePath;
      await File(path).writeAsBytes(imageBytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasAutosaveKey, true);
    } catch (e) {
      debugPrint('Errore autosalvataggio: $e');
    }
  }

  static Future<bool> hasAutosave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasAutosaveKey) ?? false;
  }

  static Future<Uint8List?> loadAutosave() async {
    try {
      final path = await _autosavePath;
      final file = File(path);
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      debugPrint('Errore caricamento autosave: $e');
    }
    return null;
  }

  static Future<void> clearAutosave() async {
    try {
      final path = await _autosavePath;
      final file = File(path);
      if (await file.exists()) await file.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasAutosaveKey, false);
    } catch (e) {
      debugPrint('Errore pulizia autosave: $e');
    }
  }
}
