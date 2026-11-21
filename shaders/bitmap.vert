uniform BitmapFrame {
  vec4 origin_viewport;
  vec4 axes;
} frame;
in vec2 position;
out vec2 uv;
void main() {
  uv = position;
  vec2 screen = frame.origin_viewport.xy + position.x * frame.axes.xy + position.y * frame.axes.zw;
  vec2 clip = 2.0 * screen / frame.origin_viewport.zw - 1.0;
  gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);
}
