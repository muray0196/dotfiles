#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Blur {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 stepUV;
  float sigma;
};
layout(binding = 1) uniform sampler2D source;

vec3 linearColor(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 displayColor(vec3 c) {
  return mix(c * 12.92, 1.055 * pow(max(c, 0.0), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
  vec3 color = vec3(0.0);
  float total = 0.0;
  // Contiguous samples at half resolution avoid the repeated-line artifacts
  // of a sparse kernel with widely separated taps.
  for (int i = -10; i <= 10; ++i) {
    float weight = exp(-0.5 * float(i * i) / (sigma * sigma));
    color += linearColor(texture(source, qt_TexCoord0 + float(i) * stepUV).rgb) * weight;
    total += weight;
  }
  fragColor = vec4(displayColor(color / total), 1.0) * qt_Opacity;
}
