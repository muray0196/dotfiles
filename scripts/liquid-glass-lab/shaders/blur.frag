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
#ifdef GLASS_ADJACENT_TAPS
  // Only for a linear input with one-texel spacing. Bilinear interpolation
  // combines each adjacent pair without dropping any of the Gaussian weights.
  vec3 color = texture(source, qt_TexCoord0).rgb;
  float total = 1.0;
  for (int i = 1; i < 10; i += 2) {
    float a = exp(-0.5 * float(i * i) / (sigma * sigma));
    float b = exp(-0.5 * float((i + 1) * (i + 1)) / (sigma * sigma));
    float weight = a + b;
    vec2 offset = (float(i) + b / weight) * stepUV;
    color += (texture(source, qt_TexCoord0 + offset).rgb
              + texture(source, qt_TexCoord0 - offset).rgb) * weight;
    total += 2.0 * weight;
  }
#else
  vec3 color = vec3(0.0);
  float total = 0.0;
  // Contiguous samples at half resolution avoid the repeated-line artifacts
  // of a sparse kernel with widely separated taps.
  for (int i = -10; i <= 10; ++i) {
    float weight = exp(-0.5 * float(i * i) / (sigma * sigma));
    vec3 sampleColor = texture(source, qt_TexCoord0 + float(i) * stepUV).rgb;
#ifndef GLASS_LINEAR_INPUT
    sampleColor = linearColor(sampleColor);
#endif
    color += sampleColor * weight;
    total += weight;
  }
#endif
  color /= total;
#ifndef GLASS_LINEAR_OUTPUT
  color = displayColor(color);
#endif
  fragColor = vec4(color, 1.0) * qt_Opacity;
}
