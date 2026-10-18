#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Study {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  float mode;
  vec2 lightDirection;
  float dark;
};
layout(binding = 1) uniform sampler2D source;
void main() {
  vec2 uv = qt_TexCoord0;
  vec3 color;
  if (mode < 0.5) {
    // Source-only approximation fitted to unobstructed margins of the WWDC
    // 2:34 boundary frame. The former flat grey ramps obscured its blue cast
    // and illumination gradient. No glass pixels or material corrections here.
    vec3 upper = vec3(0.516, 0.535, 0.596)
               + vec3(0.107, 0.112, 0.102) * uv.x
               + vec3(0.557, 0.549, 0.553) * uv.y
               - vec3(0.204, 0.192, 0.176) * uv.x * uv.x
               - vec3(0.296, 0.270, 0.274) * uv.x * uv.y
               - vec3(0.133, 0.178, 0.243) * uv.y * uv.y;
    vec3 lower = vec3(0.168, 0.172, 0.225)
               + vec3(0.196, 0.182, 0.168) * uv.x
               + vec3(0.145, 0.154, 0.097) * uv.y
               - vec3(0.238, 0.205, 0.184) * uv.x * uv.x
               - vec3(0.216, 0.203, 0.209) * uv.x * uv.y
               - vec3(0.018, 0.039, 0.014) * uv.y * uv.y;
    color = mix(upper, lower, step(0.5, uv.y));
  } else if (mode < 1.5) {
    vec2 p = (uv - 0.5) * vec2(viewSize.x / viewSize.y, 1.0);
    // Use the same projected source as the material, normalized by scene height.
    vec2 delta = p - normalize(lightDirection) * length(viewSize) / (2.0 * viewSize.y);
    float glow = exp(-dot(delta, delta) / 0.9);
    color = vec3(0.025, 0.03, 0.04) + glow * vec3(0.56, 0.59, 0.69);
  } else {
    vec2 imageSize = vec2(textureSize(source, 0));
    float cover = max(viewSize.x / imageSize.x, viewSize.y / imageSize.y);
    vec2 sampleUV = 0.5 + (uv - 0.5) * viewSize / (imageSize * cover);
    vec3 rgb = texture(source, sampleUV).rgb;
    float gray = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    color = vec3(smoothstep(0.04, 0.76, gray));
  }
  fragColor = vec4(color * mix(1.0, 0.35, dark), 1.0) * qt_Opacity;
}
