#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Photo {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  float sourceScale;
};
layout(binding = 1) uniform sampler2D source;

void main() {
  vec2 imageSize = vec2(textureSize(source, 0));
  float cover = max(viewSize.x / imageSize.x, viewSize.y / imageSize.y);
  vec2 uv = 0.5 + (qt_TexCoord0 - 0.5) * viewSize / (imageSize * cover) * sourceScale;
  vec2 inset = 0.5 / imageSize;
  fragColor = texture(source, clamp(uv, inset, 1.0 - inset)) * qt_Opacity;
}
