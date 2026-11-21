uniform sampler2D exposure;
uniform ScanInfo { vec4 scan; } info;
in vec2 uv;
out vec4 frag_color;
void main() {
  vec2 dimensions = info.scan.xy;
  vec2 pixel = clamp(floor(uv * dimensions), vec2(0.0), dimensions - 1.0);
  bool reverse = mod(pixel.y + info.scan.w, 2.0) > 0.5;
  float column = reverse ? dimensions.x - 1.0 - pixel.x : pixel.x;
  float remaining = info.scan.z - pixel.y;
  if (remaining < (column + 0.5) / dimensions.x) discard;
  float alpha = texture(exposure, (pixel + 0.5) / dimensions).r;
  frag_color = vec4(0.0, 0.0, 0.0, alpha);
}
