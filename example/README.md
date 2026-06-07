# gcode_core example

Flutter example for the `gcode_core` package.

It demonstrates the full local workflow:

- Pick a local `.gcode`, `.nc`, `.tap`, or `.txt` file.
- Read the file line by line with `FileGcodeLineReader`.
- Parse supported `G0/G1` commands with `GcodeReadlinePipeline`.
- Show command, error, and toolpath statistics.
- Draw rapid and linear toolpath segments with `CustomPainter`.

Run it from this directory:

```bash
flutter run
```
