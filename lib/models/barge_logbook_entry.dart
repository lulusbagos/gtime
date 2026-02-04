class BargeLogbookEntry {
  BargeLogbookEntry({
    required this.localId,
    required this.tugboatName,
    required this.bargeName,
    required this.captainName,
    required this.crewCount,
    required this.departurePort,
    required this.arrivalPort,
    required this.route,
    required this.weather,
    required this.seaState,
    required this.wind,
    required this.note,
    required this.date,
    required this.time,
    required this.fuelLevel,
    required this.fuelUsed,
    required this.distanceNm,
    required this.speedKnots,
    required this.engineHoursMain,
    required this.engineHoursGen,
    required this.cargoType,
    required this.cargoTonnage,
    required this.engineMain,
    required this.engineGen,
    required this.navLights,
    required this.radio,
    required this.safetyGear,
    required this.hullCheck,
    required this.crewReady,
    required this.synced,
  });

  final String localId;
  final String tugboatName;
  final String bargeName;
  final String captainName;
  final int crewCount;
  final String departurePort;
  final String arrivalPort;
  final String route;
  final String weather;
  final String seaState;
  final String wind;
  final String note;
  final String date;
  final String time;
  final int fuelLevel;
  final int fuelUsed;
  final double distanceNm;
  final double speedKnots;
  final double engineHoursMain;
  final double engineHoursGen;
  final String cargoType;
  final double cargoTonnage;
  final bool engineMain;
  final bool engineGen;
  final bool navLights;
  final bool radio;
  final bool safetyGear;
  final bool hullCheck;
  final bool crewReady;
  final bool synced;

  BargeLogbookEntry copyWith({bool? synced}) {
    return BargeLogbookEntry(
      localId: localId,
      tugboatName: tugboatName,
      bargeName: bargeName,
      captainName: captainName,
      crewCount: crewCount,
      departurePort: departurePort,
      arrivalPort: arrivalPort,
      route: route,
      weather: weather,
      seaState: seaState,
      wind: wind,
      note: note,
      date: date,
      time: time,
      fuelLevel: fuelLevel,
      fuelUsed: fuelUsed,
      distanceNm: distanceNm,
      speedKnots: speedKnots,
      engineHoursMain: engineHoursMain,
      engineHoursGen: engineHoursGen,
      cargoType: cargoType,
      cargoTonnage: cargoTonnage,
      engineMain: engineMain,
      engineGen: engineGen,
      navLights: navLights,
      radio: radio,
      safetyGear: safetyGear,
      hullCheck: hullCheck,
      crewReady: crewReady,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'tugboatName': tugboatName,
        'bargeName': bargeName,
        'captainName': captainName,
        'crewCount': crewCount,
        'departurePort': departurePort,
        'arrivalPort': arrivalPort,
        'route': route,
        'weather': weather,
        'seaState': seaState,
        'wind': wind,
        'note': note,
        'date': date,
        'time': time,
        'fuelLevel': fuelLevel,
        'fuelUsed': fuelUsed,
        'distanceNm': distanceNm,
        'speedKnots': speedKnots,
        'engineHoursMain': engineHoursMain,
        'engineHoursGen': engineHoursGen,
        'cargoType': cargoType,
        'cargoTonnage': cargoTonnage,
        'engineMain': engineMain,
        'engineGen': engineGen,
        'navLights': navLights,
        'radio': radio,
        'safetyGear': safetyGear,
        'hullCheck': hullCheck,
        'crewReady': crewReady,
        'synced': synced,
      };

  factory BargeLogbookEntry.fromJson(Map<String, dynamic> json) {
    return BargeLogbookEntry(
      localId: json['localId']?.toString() ?? '',
      tugboatName: (json['tugboatName']?.toString() ??
              json['vesselName']?.toString()) ??
          '',
      bargeName: json['bargeName']?.toString() ?? '',
      captainName: json['captainName']?.toString() ?? '',
      crewCount: (json['crewCount'] as num?)?.toInt() ?? 0,
      departurePort: json['departurePort']?.toString() ?? '',
      arrivalPort: json['arrivalPort']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      weather: json['weather']?.toString() ?? '',
      seaState: json['seaState']?.toString() ?? '',
      wind: json['wind']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      fuelLevel: (json['fuelLevel'] as num?)?.toInt() ?? 0,
      fuelUsed: (json['fuelUsed'] as num?)?.toInt() ?? 0,
      distanceNm: (json['distanceNm'] as num?)?.toDouble() ?? 0,
      speedKnots: (json['speedKnots'] as num?)?.toDouble() ?? 0,
      engineHoursMain: (json['engineHoursMain'] as num?)?.toDouble() ?? 0,
      engineHoursGen: (json['engineHoursGen'] as num?)?.toDouble() ?? 0,
      cargoType: json['cargoType']?.toString() ?? '',
      cargoTonnage: (json['cargoTonnage'] as num?)?.toDouble() ?? 0,
      engineMain: json['engineMain'] == true,
      engineGen: json['engineGen'] == true,
      navLights: json['navLights'] == true,
      radio: json['radio'] == true,
      safetyGear: json['safetyGear'] == true,
      hullCheck: json['hullCheck'] == true,
      crewReady: json['crewReady'] == true,
      synced: json['synced'] == true,
    );
  }
}
