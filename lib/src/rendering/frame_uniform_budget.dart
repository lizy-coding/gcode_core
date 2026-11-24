/// The aligned byte size reserved for a uniform block within a frame.
int alignedUniformBytes(int bytes, int alignment) =>
    ((bytes + alignment - 1) ~/ alignment) * alignment;

/// Capacity for a full frame, including the two guide draws and vector base.
int frameUniformCapacity({
  required int alignment,
  required int guideVertexBytes,
  required int guideFragmentBytes,
  required int pathVertexBytes,
  required int pathFragmentBytes,
  required int bitmapVertexBytes,
  required int bitmapFragmentBytes,
  required int vectorDraws,
  required int bitmapDraws,
}) {
  int aligned(int bytes) => alignedUniformBytes(bytes, alignment);
  return aligned(guideVertexBytes) +
      2 * aligned(guideFragmentBytes) +
      (vectorDraws == 0 ? 0 : aligned(pathVertexBytes)) +
      vectorDraws * aligned(pathFragmentBytes) +
      bitmapDraws * (aligned(bitmapVertexBytes) + aligned(bitmapFragmentBytes));
}
