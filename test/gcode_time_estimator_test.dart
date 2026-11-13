import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  group('Gcode machining time', () {
    test(
      'counts G0 and modal lines using independent jump and mark speeds',
      () {
        final result = estimateGcodeTime(
          'G0 F600 X10\nX20\nG1 F300 X30\nG0 X40',
        );
        expect(result.estimatedSeconds, 5);
        expect(result.issues, isEmpty);
      },
    );

    test('uses the last repeated coordinate or feed parameter', () {
      for (final source in [
        'G1 X1 X10 F60',
        'G1 Y1 Y10 F60',
        'G1 X10 F30 F60',
      ]) {
        final result = estimateGcodeTime(source);
        expect(result.estimatedSeconds, 10, reason: source);
        expect(result.issues, isEmpty, reason: source);
      }
    });

    test('counts zero-distance points and modal exposure lines', () {
      expect(
        estimateGcodeTime('G25 T1000\nT2000').estimatedSeconds,
        closeTo(.0034, 1e-10),
      );
    });

    test('M202 interpolation and cap apply to G25 jump plus exposure', () {
      final result = estimateGcodeTime(
        'M202 L100 H300 N10\nG0 F600\nG25 X5 T1000\nG25 X25 T1000',
      );
      expect(result.estimatedSeconds, closeTo(2.5025, 1e-10));
    });

    test('combined M202/G25 and zero maximum distance', () {
      expect(
        estimateGcodeTime('M202 L100 H300 N0 G25 T1000').estimatedSeconds,
        closeTo(.0011, 1e-10),
      );
    });

    test(
      'axis standalone movement subtracts offset and does not switch mode',
      () {
        expect(
          estimateGcodeTime('G0 F600\nG102 O0 H0 N1000 F1000\nG0 Y0')
              .estimatedSeconds,
          closeTo(1.2, 1e-10),
        );
        expect(
          estimateGcodeTime(
            'G0 F600\nG102 O0 H1 N-1000 F1000\nG0 X0',
            options: const GcodeTimeOptions(
              initialXMode: false,
              pulsePerMm: 500,
            ),
          ).estimatedSeconds,
          closeTo(1.4, 1e-10),
        );
      },
    );

    test('G103 switches axis and motion mode and uses specified time', () {
      final result = estimateGcodeTime(
        'G1 F600\nG103 X0 Y0 T1000000 L1 N1000 O0\nX10',
      );
      expect(result.estimatedSeconds, 2);
    });

    test('stationary durations and final waits are not filtered out', () {
      expect(
        estimateGcodeTime('G103 T1000000 L0 N0 O0\nG4 T1000').estimatedSeconds,
        2,
      );
    });

    test('homing is excluded by the supplied model', () {
      expect(estimateGcodeTime('G102 O1 H0 N1000 F1000').estimatedSeconds, 0);
    });

    test('returns to rapid modal movement after excluded homing', () {
      final result = estimateGcodeTime(
        'G0 F600\nG1 F300 X10\nG102 O1 H0 N1000 F1000\nX20\nY10',
      );
      expect(result.estimatedSeconds, 4);
      expect(result.issues, isEmpty);
    });

    test('relative coordinates, signed values, comments and compact words', () {
      final result = estimateGcodeTime(
        'g0f60x+1y0 ; G25 T999\nG91\nX-1 (G103 T5)\nG90\nG0X.5Y0',
      );
      expect(result.estimatedSeconds, 2.5);
    });

    test('ignores semicolons inside parentheses and trailing comments', () {
      final result = estimateGcodeTime(
        '(header; G1 X99)\nG0 F60 (axis;mm) X1 ; G0 X99\n; finish',
      );
      expect(result.estimatedSeconds, 1);
      expect(result.issues, isEmpty);
    });

    test(
      'unknown speed or unsupported motion cannot return a full estimate',
      () {
        for (final source in [
          'G0 X10',
          'G1 X10',
          'G25 X10 T1000',
          'G2 X10 F600',
          'M999 T1000',
        ]) {
          final result = estimateGcodeTime(source);
          expect(result.estimatedSeconds, isNull, reason: source);
          expect(result.isComplete, isFalse);
          expect(result.issues.single.lineNumber, 1);
        }
      },
    );

    test(
      'missing exposure, malformed input and invalid axis data are explicit',
      () {
        for (final source in [
          'G25',
          'G0 Xno',
          'G102 O0 H1 N1000 F0',
          'G102 O0 H1 N1000',
          'G103 T1 L1 N1',
          'G103 T-1 L1 N1 O0',
          'G103 T1 L1 N.5 O0',
          'M202 L700 H200 N20',
          'G25 T-1',
          'G0 Z10 F600',
          'G90 X10',
          'G0 F0',
        ]) {
          expect(
            estimateGcodeTime(source).estimatedSeconds,
            isNull,
            reason: source,
          );
        }
      },
    );

    test('initial feeds are mm/min and earlier snapshots remain immutable', () {
      final timer = GcodeTimeEstimator(
        options: const GcodeTimeOptions(rapidFeedRate: 600),
      );
      timer.append('G0 X10');
      final first = timer.snapshot;
      timer.append('G2 X20');
      expect(first.estimatedSeconds, 1);
      expect(first.issues, isEmpty);
      expect(timer.snapshot.estimatedSeconds, isNull);
      expect(
        () => first.issues.add(
          const GcodeTimingIssue(lineNumber: 1, message: 'bad'),
        ),
        throwsUnsupportedError,
      );
    });

    test('invalid calibration is rejected before loading', () {
      for (final pulse in [0.0, -1.0, double.infinity, double.nan]) {
        expect(
          () =>
              GcodeTimeEstimator(options: GcodeTimeOptions(pulsePerMm: pulse)),
          throwsArgumentError,
        );
      }
    });
  });
}
