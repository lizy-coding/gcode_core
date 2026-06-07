# gcode_core

Pure Dart G-code core extracted from `flutter_study`.

## Scope

- Read G-code from strings or files line by line.
- Parse G0/G1 commands with X/Y/F parameters.
- Collect parse errors with line metadata.
- Build incremental or batch toolpath segments.

This package contains no Flutter UI, animation, canvas drawing, or file picker code.

## Test

```bash
dart test
```

## Example

Run the executable example:

```bash
dart run example/gcode_core_example.dart
```

Minimal usage:

```dart
import 'package:gcode_core/gcode_core.dart';

Future<void> main() async {
  const source = '''
G0 X0 Y0
G1 X10 Y0 F1200
G1 X10 Y10
''';

  final pipeline = GcodeReadlinePipeline();

  await for (final snapshot
      in pipeline.load(const StringGcodeLineReader(source))) {
    if (snapshot.stage == GcodeLoadStage.ready) {
      print(snapshot.commands.length);
      print(snapshot.segments.length);
      print(snapshot.errors.length);
    }
  }
}
```
