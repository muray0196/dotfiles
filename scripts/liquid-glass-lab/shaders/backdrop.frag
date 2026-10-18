#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Background {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 sceneSize;
  float phase;
  float pattern;
  float dark;
};

void main() {
  vec2 uv = qt_TexCoord0;
  vec2 px = uv * sceneSize;
  vec3 color;
  if (pattern < 0.5) {
    color = mix(vec3(0.89, 0.94, 0.98), vec3(0.98, 0.91, 0.86), uv.y);
    vec2 a = uv - vec2(0.24 + 0.08 * sin(phase), 0.23);
    vec2 b = uv - vec2(0.72, 0.60 + 0.10 * cos(phase * 0.7));
    color = mix(color, vec3(0.16, 0.47, 0.94), exp(-dot(a * vec2(2.2, 2.6), a * vec2(2.2, 2.6))) * 0.88);
    color = mix(color, vec3(0.91, 0.27, 0.30), exp(-dot(b * vec2(2.6, 2.8), b * vec2(2.6, 2.8))) * 0.83);
    float ribbon = uv.y - 0.35 - 0.17 * sin(uv.x * 6.0 + phase * 0.3);
    color = mix(color, vec3(0.98, 0.67, 0.26), (1.0 - smoothstep(0.068, 0.075, abs(ribbon))) * 0.72);
  } else if (pattern < 1.5) {
    color = vec3(0.95, 0.96, 0.975);
    vec2 cell = abs(mod(px + vec2(phase * 15.0, 0.0), 28.0) - 14.0);
    float grid = 1.0 - smoothstep(0.45, 1.05, min(cell.x, cell.y));
    color = mix(color, vec3(0.35, 0.44, 0.56), grid * 0.65);
    float stripe = abs(mod(px.x + phase * 15.0, 140.0) - 70.0);
    color = mix(color, vec3(0.12, 0.44, 0.91), 1.0 - smoothstep(1.0, 1.8, stripe));
  } else if (pattern < 2.5) {
    color = mix(vec3(0.91, 0.94, 0.96), vec3(0.99, 0.91, 0.80), uv.x);
  } else {
    float split = 0.5 + 0.28 * sin(phase * 0.7);
    color = mix(vec3(0.10, 0.14, 0.23), vec3(0.98, 0.98, 0.95), step(split, uv.x));
    float stripe = abs(mod(px.y, 32.0) - 16.0);
    color = mix(color, vec3(0.96, 0.35, 0.16), 1.0 - smoothstep(0.5, 1.4, stripe));
  }
  color = mix(color, color * 0.24 + vec3(0.025, 0.035, 0.055), dark);
  fragColor = vec4(color, 1.0) * qt_Opacity;
}
