#version 300 es
precision highp float;

// Experimental Clear material. Compositor coordinates and coverage are the
// adapter; no previous optical uniforms or rim-colour treatments are consumed.
uniform sampler2D tex;
uniform sampler2D maskTex;
uniform vec2 fullSize;
uniform vec2 glassBoxOffsetPx;
uniform vec2 glassBoxSizePx;
uniform vec4 radii;
uniform vec2 uvPadding;
uniform vec2 sampleUVOffset;
uniform vec2 sampleUVScale;
uniform vec2 maskUVOffset;
uniform vec2 maskUVScale;
uniform int useMask;
uniform int maskMode;
uniform int regionRectCount;
uniform vec4 regionRects[64];
uniform float maskAlphaThreshold;
uniform float maskCoverage;
uniform float glassOpacity;
uniform float monitorScale;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

// Designed screen-space lens. A radius-relative ray excursion produces the
// returned background image; it is not a separately painted perimeter band.
const float LENS_SUPPORT = 0.50;
const float EDGE_TRAVEL = 1.30;
const float RAY_SPREAD = 0.060;
const float LIGHT_STRENGTH = 0.65;
const float CONTENT_BACKING = 0.28;

struct Shape {
  float distance;
  float radius;
  vec2 normal;
};

Shape shapeAt(vec2 pixel) {
  vec2 p = pixel - glassBoxOffsetPx - 0.5 * glassBoxSizePx;
  float r = p.y < 0.0 ? (p.x < 0.0 ? radii.x : radii.y)
             : (p.x < 0.0 ? radii.w : radii.z);
  r = min(max(r, 0.001), 0.5 * min(glassBoxSizePx.x, glassBoxSizePx.y));
  vec2 q = abs(p) - 0.5 * glassBoxSizePx + r;
  vec2 outside = max(q, 0.0);
  float l = length(outside);
  Shape s;
  s.distance = l + min(max(q.x, q.y), 0.0) - r;
  s.radius = r;
  s.normal = l > 0.0001 ? sign(p) * outside / l
    : (q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y)));
  return s;
}

vec2 sourcePoint(vec2 pixel) {
  Shape s = shapeAt(pixel);
  float depth = max(-s.distance, 0.0);
  float t = clamp(depth / (LENS_SUPPORT * s.radius), 0.0, 1.0);
  // Circular sag goes continuously to a stationary clear face. Integrate
  // across the output pixel below, including the steep grazing portion.
  float sag = 1.0 - sqrt(max(t * (2.0 - t), 0.0));
  return pixel - s.normal * (s.radius * EDGE_TRAVEL * sag);
}

vec2 backgroundUV(vec2 pixel) {
  vec2 boxUV = (pixel / fullSize - sampleUVOffset) / sampleUVScale;
  vec2 uv = boxUV * (1.0 - 2.0 * uvPadding) + uvPadding;
  vec2 halfTexel = 0.5 / vec2(textureSize(tex, 0));
  return clamp(uv, halfTexel, vec2(1.0) - halfTexel);
}

vec3 transmission(vec2 pixel, out float nonlinearity) {
  vec2 source = sourcePoint(pixel);
  vec2 uv = backgroundUV(source);
  // Explicit differences describe the source footprint even in the adaptive
  // sampling branch. The second difference detects curvature within a pixel.
  vec2 right = sourcePoint(pixel + vec2(0.5, 0.0));
  vec2 left = sourcePoint(pixel - vec2(0.5, 0.0));
  vec2 bottom = sourcePoint(pixel + vec2(0.0, 0.5));
  vec2 top = sourcePoint(pixel - vec2(0.0, 0.5));
  vec2 dx = backgroundUV(right) - backgroundUV(left);
  vec2 dy = backgroundUV(bottom) - backgroundUV(top);
  nonlinearity = max(length(right + left - 2.0 * source),
                    length(bottom + top - 2.0 * source));
  // A small angular spread accumulates with the ray's travel through the
  // roundover. Add it to the sampling footprint in source space; the flat
  // centre has zero travel and retains its original resolution.
  vec2 pixelUV = (1.0 - 2.0 * uvPadding) / (fullSize * sampleUVScale);
  vec2 spread = pixelUV * (RAY_SPREAD * length(source - pixel));
  // Resolve the footprint's principal axes in texel space. Mips cover the
  // short axis; a continuous eight-tap footprint covers the long axis. This
  // avoids driver-dependent anisotropy and jumps from changing tap counts.
  vec2 texels = vec2(textureSize(tex, 0));
  dx *= texels;
  dy *= texels;
  spread *= texels;
  float xx = dx.x*dx.x + dy.x*dy.x + spread.x*spread.x;
  float xy = dx.x*dx.y + dy.x*dy.y;
  float yy = dx.y*dx.y + dy.y*dy.y + spread.y*spread.y;
  float delta = length(vec2(xx - yy, 2.0 * xy));
  float large = max(0.5 * (xx + yy + delta), 1e-8);
  float small = max(0.5 * (xx + yy - delta), 1e-8);
  vec2 axis = vec2(xy, large - xx);
  axis = dot(axis, axis) > 1e-12 ? normalize(axis) : vec2(1.0, 0.0);
  float minor = max(max(sqrt(small), sqrt(large) / 8.0), 1.0);
  float lod = log2(minor);
  float span = sqrt(max(large - minor*minor, 0.0));
  if (span < 0.01) return textureLod(tex, uv, lod).rgb;
  vec2 stepUV = axis * (span / 8.0) / texels;
  vec3 sum = vec3(0.0);
  for (int i = 0; i < 8; ++i) {
    sum += textureLod(tex, uv + stepUV * (float(i) - 3.5), lod).rgb;
  }
  return sum * 0.125;
}

// An elongated source extends around the silhouette while preserving its
// radial falloff. The face sees the same response as a round source.
float areaLight(vec3 reflected, vec3 direction, float spread) {
  vec3 tangent = normalize(vec3(-direction.y, direction.x, 0.0));
  vec3 bitangent = cross(direction, tangent);
  vec2 projected = vec2(dot(reflected, tangent), dot(reflected, bitangent));
  float radial = dot(projected, projected);
  vec2 stretched = projected / vec2(1.35, 1.0);
  float aspect = radial > 1e-8 ? dot(stretched, stretched) / radial : 1.0;
  float angularDistance = 1.0 - clamp(dot(reflected, direction), -1.0, 1.0);
  return exp(-angularDistance * aspect / (spread * spread));
}

vec3 illuminate(vec3 transmitted, Shape s) {
  float scale = max(monitorScale, 0.001);
  float width = (4.5 * scale + 0.09 * s.radius);
  float t = clamp(-s.distance / width, 0.0, 1.0);
  // Cross-section of an elliptical roundover. Unlike transmission, this is
  // an actual surface normal used only to reflect a simple virtual light rig.
  float q = 1.0 - t;
  vec3 n = normalize(vec3(s.normal * (0.65 * q), sqrt(max(1.0 - q*q, 0.0))));
  vec3 reflected = reflect(vec3(0.0, 0.0, -1.0), n);
  vec3 key = normalize(vec3(-0.707, -0.707, 0.10));
  vec3 fill = normalize(vec3(0.72, 0.69, 0.10));
  float light = areaLight(reflected, key, 0.32)
        + 0.78 * areaLight(reflected, fill, 0.28);
  light += 0.10 * areaLight(reflected, key, 0.55)
     + 0.06 * areaLight(reflected, fill, 0.48);
  // A neutral light response. All coloured folds remain transported imagery.
  // No normalizing of dark scene colours, no borrowed far-away rim colour.
  // Two weak dark areas in the same virtual environment define the unlit
  // shoulders on white. Their response follows the reflected direction,
  // rather than introducing another distance-based border or global tint.
  vec3 flag = normalize(vec3(0.866, -0.50, 0.10));
  float occlusion = 0.045 * areaLight(reflected, flag, 0.38)
          + 0.025 * areaLight(reflected, vec3(-flag.xy, flag.z), 0.38);
  return mix(transmitted * (1.0 - occlusion), vec3(1.0),
       clamp(LIGHT_STRENGTH * light, 0.0, 1.0));
}

void main() {
  vec2 pixel = v_texcoord * fullSize;
  vec4 surface = vec4(0.0);
  float mask = 1.0;
  if (useMask == 1) {
    surface = textureLod(maskTex, clamp(v_texcoord * maskUVScale + maskUVOffset, 0.001, 0.999), 0.0);
    if (maskMode == 1) {
      bool inside = false;
      for (int i = 0; i < regionRectCount; ++i) {
        vec4 r = regionRects[i];
        inside = inside || (all(greaterThanEqual(pixel, r.xy))
          && all(lessThanEqual(pixel, r.xy + r.zw)));
      }
      if (!inside) { fragColor = surface; return; }
    } else {
      if (surface.a < maskAlphaThreshold) { fragColor = surface; return; }
      if (maskCoverage > 0.0) {
        float v = clamp((surface.a - maskAlphaThreshold) / maskCoverage, 0.0, 1.0);
        mask = v*v*(3.0-2.0*v);
      }
    }
  }
  Shape s = shapeAt(pixel);
  float coverage = 1.0 - smoothstep(-0.75, 0.75, s.distance);
  if (coverage <= 0.0) {
    fragColor = surface; return;
  }
  float nonlinearity;
  vec3 color = transmission(pixel, nonlinearity);
  vec3 unlit = color;
  color = 0.25 * (illuminate(unlit, shapeAt(pixel + vec2(-0.25, -0.25)))
         + illuminate(unlit, shapeAt(pixel + vec2( 0.25, -0.25)))
         + illuminate(unlit, shapeAt(pixel + vec2(-0.25,  0.25)))
         + illuminate(unlit, shapeAt(pixel + vec2( 0.25,  0.25))));
  // At grazing angles the ray map can bend substantially within one pixel.
  // A single derivative ellipse cannot describe that footprint. Integrate
  // four rays only where the measured second difference calls for it.
  if (nonlinearity > 0.20) {
    vec3 integrated = vec3(0.0);
    for (int y = 0; y < 2; ++y) {
      for (int x = 0; x < 2; ++x) {
        vec2 p = pixel + vec2(float(x) - 0.5, float(y) - 0.5) * 0.5;
        float unused;
        integrated += illuminate(transmission(p, unused), shapeAt(p));
      }
    }
    color = mix(color, integrated * 0.25, smoothstep(0.20, 0.75, nonlinearity));
  }
  // Foreground legibility is a separate compositing concern. Empty glass has
  // no global dimming, adaptive frosting, saturation adjustment, or tint.
  if (useMask == 1) {
    vec2 uv = v_texcoord * maskUVScale + maskUVOffset;
    vec2 pixelUV = 1.0 / vec2(textureSize(maskTex, 0));
    float lod = log2(max(3.0 * monitorScale, 1.0));
    vec2 spread = pixelUV * 3.0 * monitorScale;
    float density = 0.5 * textureLod(maskTex, uv, lod).a;
    density += 0.125 * textureLod(maskTex, uv + vec2(spread.x, spread.y), lod).a;
    density += 0.125 * textureLod(maskTex, uv + vec2(-spread.x, spread.y), lod).a;
    density += 0.125 * textureLod(maskTex, uv + vec2(spread.x, -spread.y), lod).a;
    density += 0.125 * textureLod(maskTex, uv - spread, lod).a;
    float backing = smoothstep(0.065, 0.23, density);
    color *= 1.0 - CONTENT_BACKING * backing;
  }
  float alpha = clamp(glassOpacity * coverage * mask, 0.0, 1.0);
  vec4 glass = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
  fragColor = (surface + glass * (1.0 - surface.a));
}
