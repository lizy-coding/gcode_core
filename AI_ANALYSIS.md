{
  "schema": "vibecoding.harness.ai_analysis.v1",
  "mode": "harness",
  "node": {
    "id": "packages.gcode_core",
    "kind": "dart_package",
    "package": "gcode_core",
    "path": "../gcode_core",
    "status": "active"
  },
  "entrypoints": ["lib/gcode_core.dart"],
  "owns": ["gcode_readers","gcode_parser","gcode_domain","gcode_toolpath","gcode_pipeline"],
  "depends": ["dart_sdk"],
  "mutates": ["lib/**","test/**","pubspec.yaml","AI_ANALYSIS.md"],
  "files": ["README.md","lib/gcode_core.dart","lib/src/application/gcode_readline_pipeline.dart","lib/src/data/readers/file_gcode_line_reader.dart","lib/src/data/readers/gcode_line_reader.dart","lib/src/data/readers/string_gcode_line_reader.dart","lib/src/domain/gcode_line_record.dart","lib/src/domain/gcode_load_snapshot.dart","lib/src/domain/gcode_load_stage.dart","lib/src/domain/parsed_gcode_line.dart","lib/src/models/gcode_command.dart","lib/src/models/machine_position.dart","lib/src/models/toolpath_segment.dart","lib/src/parser/gcode_parse_result.dart","lib/src/parser/gcode_parser.dart","lib/src/services/toolpath_builder.dart","pubspec.lock","pubspec.yaml","test/application/gcode_readline_pipeline_test.dart","test/gcode_parser_test.dart","test/toolpath_builder_test.dart"],
  "contracts": {
    "no_natural_language": true,
    "doc_consumer": "vibecoding",
    "doc_mode": "harness",
    "update_required_on_file_change": true,
    "import_direction_enforced": true
  },
  "validation": ["dart format .","dart analyze","dart test"]
}
