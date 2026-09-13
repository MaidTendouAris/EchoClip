import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Display ballistics only; input remains unmodified linear RMS/sample peak.
class LoudnessMeterModel extends ChangeNotifier {
  static const floorDb = -60.0;
  static const historyIntervals = 120;
  // Keep the segment crossing the left edge, including its offscreen endpoint.
  static const historyLength = historyIntervals + 2;
  final history = <double>[];
  final reading = ValueNotifier(const MeterReading(null, null, false));
  bool active = false;
  double levelDb = floorDb;
  double peakDb = floorDb;
  double _target = floorDb;
  double _inputPeak = floorDb;
  double _peakHold = 0;
  double _sampleTime = 0;
  double _readoutTime = 0;
  bool _silent = true;
  bool _peakInputPresent = false;
  bool _interpolateHistory = true;
  double get historyPhase => _interpolateHistory ? _sampleTime / 0.05 : 0;
  double get currentDb => _target;

  static double amplitudeToDb(double value) => !value.isFinite || value <= 0
      ? double.negativeInfinity
      : 20 * math.log(value.clamp(0.0, 1.0)) / math.ln10;

  static double position(double db) =>
      ((db - floorDb) / -floorDb).clamp(0.0, 1.0);

  void setInput(double rms, double peak, {required bool recording}) {
    if (recording && !active) {
      history.clear();
      levelDb = floorDb;
      peakDb = floorDb;
      _sampleTime = 0;
      _readoutTime = 0;
      _peakHold = 0;
    }
    active = recording;
    final db = amplitudeToDb(rms);
    _silent = !db.isFinite;
    _peakInputPresent =
        (rms.isFinite && rms > 0) || (peak.isFinite && peak > 0);
    _target = db.clamp(floorDb, 0.0);
    _inputPeak = math.max(_target, amplitudeToDb(peak).clamp(floorDb, 0.0));
    if (!active) {
      levelDb = floorDb;
      peakDb = floorDb;
      reading.value = const MeterReading(null, null, false);
      notifyListeners();
    }
  }

  void advance(Duration elapsed, {bool animate = true}) {
    if (!active) return;
    _interpolateHistory = animate;
    var seconds = elapsed.inMicroseconds / 1000000;
    if (seconds > 0.5) {
      // A hidden/resumed view has no reliable observations for the gap.
      history.clear();
      _sampleTime = 0;
      seconds = 0.05;
    }
    final response = _target > levelDb ? 0.035 : 0.28;
    levelDb = animate
        ? levelDb + (_target - levelDb) * (1 - math.exp(-seconds / response))
        : _target;
    if (_inputPeak >= peakDb) {
      peakDb = _inputPeak;
      _peakHold = 1.0;
    } else {
      _peakHold -= seconds;
      if (_peakHold <= 0) {
        peakDb = math.max(_inputPeak, peakDb - 18 * seconds);
      }
    }
    peakDb = math.max(peakDb, levelDb);
    _sampleTime += seconds;
    while (_sampleTime >= 0.05) {
      _sampleTime -= 0.05;
      history.add(_target);
      if (history.length > historyLength) history.removeAt(0);
    }
    _readoutTime += seconds;
    if (_readoutTime >= 0.125 || !reading.value.active) {
      _readoutTime = 0;
      reading.value = MeterReading(
        _silent && levelDb < floorDb + 0.5 ? null : levelDb.round(),
        peakDb <= floorDb && !_peakInputPresent ? null : peakDb.round(),
        true,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    reading.dispose();
    super.dispose();
  }
}

@immutable
class MeterReading {
  const MeterReading(this.level, this.peak, this.active);
  final int? level;
  final int? peak;
  final bool active;
  static String format(int? value) => value == null
      ? '−∞'
      : value <= -60
      ? '≤−60'
      : value < 0
      ? '−${value.abs()}'
      : '$value';
}
