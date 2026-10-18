#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Fixture {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 sceneSize;
  float phase;
  float pattern;
};
void main() {
  vec2 uv = qt_TexCoord0;
  vec3 color = vec3(0.1 + 0.7 * uv.x, 0.1 + 0.7 * uv.y, 0.25 + phase * 0.2);
  if (pattern > 4.5) {
    color = uv.x < 0.5 ? vec3(0.9, 0.08, 0.02) : vec3(0.02, 0.4, 0.8);
  } else if (pattern > 3.5) {
    color = uv.x < 0.5 ? vec3(0.02) : vec3(0.98);
  } else if (pattern > 2.5) {
    bool center = uv.x * sceneSize.x > 120.0 && uv.x * sceneSize.x < 450.0
               && uv.y * sceneSize.y > 60.0 && uv.y * sceneSize.y < 330.0;
    color = center ? vec3(0.35) : mix(vec3(0.8, 0.12, 0.1), vec3(0.1, 0.14, 0.8), phase);
  } else if (pattern > 1.5) {
    color = vec3(phase);
  } else if (pattern > 0.5) {
    float square = mod(floor(uv.x * sceneSize.x / 4.0) + floor(uv.y * sceneSize.y / 4.0), 2.0);
    color = vec3(0.1 + 0.8 * square);
  }
  fragColor = vec4(color, 1.0) * qt_Opacity;
}
