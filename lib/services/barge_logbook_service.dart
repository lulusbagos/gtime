import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/models/barge_logbook_entry.dart';
import 'package:gtime/services/api_service.dart';

class BargeLogbookService {
  static const String _logbookKey = 'barge_logbook_entries';

  static Future<List<BargeLogbookEntry>> loadEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_logbookKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => BargeLogbookEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveEntries(List<BargeLogbookEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final data = entries.map((e) => e.toJson()).toList();
    await prefs.setString(_logbookKey, jsonEncode(data));
  }

  static Future<bool> syncEntry(BargeLogbookEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) return false;

      final payload = {
        'nama_tugboat': entry.tugboatName,
        'nama_barge': entry.bargeName,
        'nama_kapten': entry.captainName,
        'jumlah_kru': entry.crewCount,
        'departure_port': entry.departurePort,
        'arrival_port': entry.arrivalPort,
        'tanggal': entry.date,
        'jam': entry.time,
        'route': entry.route,
        'weather': entry.weather,
        'sea_state': entry.seaState,
        'wind': entry.wind,
        'fuel_level': entry.fuelLevel,
        'fuel_used': entry.fuelUsed,
        'distance_nm': entry.distanceNm,
        'speed_knots': entry.speedKnots,
        'engine_hours_main': entry.engineHoursMain,
        'engine_hours_gen': entry.engineHoursGen,
        'cargo_type': entry.cargoType,
        'cargo_tonnage': entry.cargoTonnage,
        'engine_main': entry.engineMain,
        'engine_gen': entry.engineGen,
        'nav_lights': entry.navLights,
        'radio': entry.radio,
        'safety_gear': entry.safetyGear,
        'hull_check': entry.hullCheck,
        'crew_ready': entry.crewReady,
        'notes': entry.note,
        'client_ref': entry.localId,
      };

      await ApiService().post(
        '/api/barge-logbook',
        body: payload,
        token: token,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
