import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/src/rendering/frame_uniform_budget.dart';

int _capacity(int alignment,
        {required int vectorDraws, required int bitmapDraws}) =>
    frameUniformCapacity(
      alignment: alignment,
      guideVertexBytes: 16,
      guideFragmentBytes: 160,
      pathVertexBytes: 16,
      pathFragmentBytes: 96,
      bitmapVertexBytes: 32,
      bitmapFragmentBytes: 16,
      vectorDraws: vectorDraws,
      bitmapDraws: bitmapDraws,
    );

void main() {
  test('64 mixed operations fit a single aligned block at full progress', () {
    // Two vector operations and a shared vector base plus 62 bitmap draws.
    expect(_capacity(256, vectorDraws: 3, bitmapDraws: 62), 131 * 256);
  });

  test('single bitmap omits vector uniforms', () {
    expect(_capacity(256, vectorDraws: 0, bitmapDraws: 1), 5 * 256);
  });

  test('blocks wider than the device alignment reserve their full size', () {
    expect(alignedUniformBytes(160, 64), 192);
    expect(_capacity(64, vectorDraws: 2, bitmapDraws: 0), 768);
  });
}
