#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Material {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 bodySize;
  vec4 sampleRect;
  vec2 backdropSize;
  float padding;
  float cornerRadius;
  float edgeWidth;
  float thickness;
  float surfaceHeight;
  float crownHeight;
  float magnification;
  float transmissionRoughness;
  float interiorFiltering;
  float softness;
  float edgeSoftness;
  float lighting;
  float ambientReflection;
  float adaptation;
  float diffusion;
  vec4 tint;
  float refraction;
  float shadowStrength;
  vec2 lightDirection;
  vec2 lightPosition;
  float diagnostic;
};
layout(binding = 1) uniform sampler2D backdrop;
layout(binding = 2) uniform sampler2D softenedBackdrop;

// Analytic geometry, evaluated in logical pixels. No content-alpha inference.
float distanceToBody(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 boundaryNormal(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  vec2 outside = max(q, 0.0);
  if (dot(outside, outside) > 0.00001)
    return sign(p) * normalize(outside);
  return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}

vec3 linearColor(vec3 color) {
  return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)),
             step(vec3(0.04045), color));
}

vec3 displayColor(vec3 color) {
  return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
             step(vec3(0.0031308), color));
}

void main() {
  vec2 extent = bodySize + 2.0 * padding;
  vec2 p = qt_TexCoord0 * extent - extent * 0.5;
  vec2 halfSize = bodySize * 0.5;
  float radius = min(cornerRadius, min(halfSize.x, halfSize.y));
  float d = distanceToBody(p, halfSize, radius);
  float aa = max(fwidth(d), 0.0001);
  float coverage = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);
  float depth = max(-d, 0.0);
  vec2 n = boundaryNormal(p, halfSize, radius);

  // A continuous cubic superellipse cross-section. Its slope and slope
  // derivative both vanish at the flat interior, avoiding a visible shoulder
  // where an arbitrary displacement band ends. Height changes the optical path
  // as well as the normal; thickness is the virtual distance below the lens.
  // This is an independent optical approximation, not an Apple shader formula.
  float bevel = max(min(edgeWidth, min(halfSize.x, halfSize.y)), 0.1);
  float t = clamp(depth / bevel, 0.0, 1.0);
  float q = 1.0 - t;
  float cap = max(1.0 - q * q * q, 0.00001);
  float heightFraction = pow(cap, 1.0 / 3.0);
  float slope = surfaceHeight / bevel * q * q / pow(cap, 2.0 / 3.0);
  vec2 normalXY = n * slope;
  float surfaceZ = surfaceHeight * heightFraction;
  if (crownHeight > 0.0) {
    // One broad quartic crown supplies a gentle lens across the interior.
    // Its height and analytic gradient taper to zero at the bounding sides;
    // multiplying by the cap closes it continuously at the rounded corners.
    // Unlike extending an SDF bevel, this has no nearest-edge seam in the core.
    vec2 u = clamp(p / halfSize, -1.0, 1.0);
    vec2 a = max(1.0 - u * u, 0.0);
    float crown = crownHeight * a.x * a.x * a.y * a.y;
    vec2 crownNormal = 4.0 * crownHeight * p / (halfSize * halfSize)
                       * vec2(a.x * a.y * a.y, a.y * a.x * a.x);
    float capSlope = q * q / (bevel * pow(cap, 2.0 / 3.0));
    normalXY += heightFraction * crownNormal + n * crown * capSlope;
    surfaceZ += crown * heightFraction;
  }
  vec3 surfaceNormal = normalize(vec3(normalXY, 1.0));
  vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 1.0 / 1.46);
  vec2 displacement = ray.xy / max(-ray.z, 0.1) * (thickness + surfaceZ);
  displacement -= p * magnification * smoothstep(0.0, bevel, depth);
  displacement *= refraction;

  vec2 pixel = sampleRect.xy + qt_TexCoord0 * sampleRect.zw;
  vec2 uv = (pixel + displacement) / backdropSize;
  // The source is a full owned scene; a desktop backend must provide padding
  // instead of relying on these outer scene boundary clamps.
  vec2 inset = 0.5 / backdropSize;
  uv = clamp(uv, inset, 1.0 - inset);
  vec3 sharp = texture(backdrop, uv).rgb;
  // A small angular spread around the transmitted ray. Projection onto the
  // background makes the footprint wider along an oblique ray (1/cos^2) than
  // across it (1/cos). This approximates weak transmission roughness, not a
  // recovered Apple model. It never mixes in a remote low-frequency backdrop.
  vec2 dx = dFdx(uv), dy = dFdy(uv);
  if (transmissionRoughness > 0.0) {
    float cosine = max(-ray.z, 0.1);
    vec2 direction = ray.xy / max(length(ray.xy), 0.0001);
    // Bound the largest standard deviation to two logical source pixels.
    float spread = min(transmissionRoughness * (thickness + surfaceZ), 2.0 * cosine * cosine);
    // Keep the entire committed bevel untouched. Beyond it, ease into interior
    // filtering with a narrower 1.6-logical-pixel bound.
    // The radius still follows optical depth and fades with material presence.
    float face = interiorFiltering * smoothstep(bevel, bevel + max(12.0, 0.75 * bevel), depth);
    spread = mix(spread, min(spread * 1.2, 1.6 * cosine * cosine), face);
    float elongation = 1.0 / cosine - 1.0;
    vec2 alongX = (vec2(1.0, 0.0) + elongation * direction * direction.x) * spread / cosine;
    vec2 alongY = (vec2(0.0, 1.0) + elongation * direction * direction.y) * spread / cosine;
    vec3 transmitted = vec3(0.0);
    vec3 encoded = vec3(0.0);
    // Cover gaps between the wider interior taps using the existing mip chain.
    // Keep the committed geometric footprint throughout the protected bevel.
    float tapFootprint = max(1.0, face * spread / cosine);
    for (int y = -2; y <= 2; ++y) {
      for (int x = -2; x <= 2; ++x) {
        // A denser binomial footprint avoids separated replicas of sharp
        // boundaries. The weights sum to one and have unit variance per axis.
        float wx = x == 0 ? 6.0 : (abs(x) == 1 ? 4.0 : 1.0);
        float wy = y == 0 ? 6.0 : (abs(y) == 1 ? 4.0 : 1.0);
        float weight = wx * wy / 256.0;
        vec2 offset = (float(x) * alongX + float(y) * alongY) / backdropSize;
        // Explicit gradients avoid unintended derivatives of the tap offsets.
        vec3 sampleColor = textureGrad(backdrop, clamp(uv + offset, inset, 1.0 - inset),
                                      dx * tapFootprint, dy * tapFootprint).rgb;
        // The flat interior uses only encoded RGB. Avoid converting taps whose
        // linear-light result would be discarded; retain it throughout the bevel.
        if (face < 1.0) transmitted += weight * linearColor(sampleColor);
        encoded += weight * sampleColor;
      }
    }
    // Perceptual filtering preserves the displayed average of mixed detail,
    // avoiding the linear-light kernel's brightness lift in the flat face.
    // This is an independent UI choice, not recovered Apple color handling.
    sharp = encoded;
    if (face < 1.0) sharp = mix(displayColor(transmitted), encoded, face);
  }
  vec3 soft = texture(softenedBackdrop, uv).rgb;
  float scattering = mix(edgeSoftness, softness, smoothstep(0.0, edgeWidth * 1.25, depth));
  vec3 material = mix(sharp, soft, scattering);

  // Local adaptation uses the shared low-frequency scene, not a fixed fill.
  vec3 ambient = texture(softenedBackdrop, clamp(pixel / backdropSize, inset, 1.0 - inset)).rgb;
  float luma = dot(ambient, vec3(0.2126, 0.7152, 0.0722));
  vec3 tone = mix(vec3(0.18, 0.20, 0.24), vec3(0.96, 0.975, 1.0), smoothstep(0.2, 0.75, luma));
  material = mix(material, tone, adaptation * (0.045 + 0.075 * scattering));

  // Tint colors the transmitted image without changing its sampling or optics.
  float support = smoothstep(0.0, min(12.0, bevel), depth);
  if (diffusion > 0.0 || tint.a > 0.0) {
    vec3 face = mix(material, soft, 0.85 * diffusion);
    face = mix(face, tint.rgb, tint.a);
    material = mix(material, face, support);
  }

  // A finite source in backdrop coordinates gives a straight edge a changing
  // incident direction along its length. A uniform direction made the whole
  // edge flash at once. Glass movement now passes through a stable light field.
  vec2 toLight = lightPosition - pixel;
  vec2 light = toLight / max(length(toLight), 0.0001);
  float facing = dot(n, light);
  float rim = exp(-pow((depth - 0.65) / 1.2, 2.0));
  float glint = pow(max(facing, 0.0), 10.0);
  float counter = pow(max(-facing, 0.0), 12.0);
  // The reference has a sharp core plus a much longer inward falloff. The
  // former two-pixel Gaussian alone read as an illuminated outline. Tie the
  // soft shoulder to the curved section, and extinguish it at the flat core.
  // This is an empirical reflection profile, not recovered Apple optics.
  float shoulderWidth = max(min(bevel * 0.24, radius * 0.08), 1.5);
  float shoulder = 1.0 / (1.0 + pow(depth / shoulderWidth, 2.0));
  shoulder *= 1.0 - smoothstep(0.55 * bevel, bevel, depth);
  float sourceLuma = clamp(luma, 0.0, 1.0);
  float broadLight = 0.30 * (1.0 - 0.5 * sourceLuma) * pow(max(facing, 0.0), 4.0)
                   + 0.21 * pow(1.0 - sourceLuma, 2.0) * pow(max(-facing, 0.0), 4.0);
  // Share the energy between the core and shoulder instead of just brightening
  // the old outline. Opposing highlights recede over a bright background.
  float counterStrength = 0.38 * pow(1.0 - clamp(luma, 0.0, 1.0), 2.0);
  material += lighting * (rim * (0.62 * glint + counterStrength * counter)
                         + shoulder * broadLight);
  float edgeShade = 0.40 * (1.0 - abs(facing)) + 0.40 * luma * pow(max(-facing, 0.0), 3.0);
  material *= 1.0 - lighting * rim * edgeShade;

  // Nearby content contributes a low-frequency reflection on the curved face.
  // Sample beyond the nearest boundary, not the already refracted material, so
  // this layer cannot feed back into itself or repaint the flat interior.
  if (ambientReflection > 0.0 && lighting > 0.0) {
    float reach = clamp(radius * 0.4, 8.0, 28.0);
    vec2 outsidePoint = pixel + n * (depth + reach);
    vec2 tangent = vec2(-n.y, n.x) * reach;
    vec3 environment = 0.5 * texture(softenedBackdrop, clamp(outsidePoint / backdropSize, inset, 1.0 - inset)).rgb;
    environment += 0.25 * texture(softenedBackdrop, clamp((outsidePoint + tangent) / backdropSize, inset, 1.0 - inset)).rgb;
    environment += 0.25 * texture(softenedBackdrop, clamp((outsidePoint - tangent) / backdropSize, inset, 1.0 - inset)).rgb;
    float reflected = ambientReflection * lighting * (1.0 - smoothstep(0.0, bevel, depth));
    material = mix(material, environment, clamp(reflected, 0.0, 0.25));
  }

  if (diagnostic > 1.5)
    material = vec3(0.5 + 0.5 * n, t);
  else if (diagnostic > 0.5)
    material = vec3(t);

  float shadowDistance = max(distanceToBody(p - vec2(0.0, 6.0), halfSize, radius), 0.0);
  float shadow = shadowStrength * exp(-0.5 * pow(shadowDistance / 7.0, 2.0)) * (1.0 - coverage);
  // Source-over, premultiplied. The sampled material is opaque inside its mask.
  float alpha = coverage + shadow;
  fragColor = vec4(clamp(material, 0.0, 1.0) * coverage, alpha) * qt_Opacity;
}
