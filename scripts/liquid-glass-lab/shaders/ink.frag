#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Ink {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 sampleRegion;
};
layout(binding = 1) uniform sampler2D glyphs;
layout(binding = 2) uniform sampler2D backdrop;
void main() {
  float luma = 0.0;
  // A common decision for the whole label group, so neighboring glyphs never
  // flip independently. This simple threshold is not an Apple material recipe.
  for (int y = 0; y < 3; ++y)
    for (int x = 0; x < 3; ++x) {
      vec2 uv = sampleRegion.xy + (vec2(x, y) + 0.5) / 3.0 * sampleRegion.zw;
      luma += dot(texture(backdrop, uv).rgb, vec3(0.2126, 0.7152, 0.0722));
    }
  luma /= 9.0;
  vec3 ink = luma < 0.50 ? vec3(0.97, 0.98, 1.0) : vec3(0.055, 0.095, 0.16);
  float alpha = texture(glyphs, qt_TexCoord0).a * qt_Opacity;
  fragColor = vec4(ink * alpha, alpha);
}
