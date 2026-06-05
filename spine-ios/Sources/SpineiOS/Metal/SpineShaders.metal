#include <metal_stdlib>
#include <simd/simd.h> 
using namespace metal;

#if __has_include("spine-ios/Sources/SpineShadersStructs/SpineShadersStructs.h")
// Cocoapods Target
    #include "spine-ios/Sources/SpineShadersStructs/SpineShadersStructs.h"
#elif  __has_include("../../SpineShadersStructs/SpineShadersStructs.h")
// Swift Package target
    #include "../../SpineShadersStructs/SpineShadersStructs.h"
#else
    #error "Header not found. Please correct Header search path"
#endif

struct RasterizerData {
    simd_float4 position [[position]];
    simd_float4 color;
    simd_float2 textureCoordinate;
    float bleach;
};

vertex RasterizerData vertexShader(
    uint vertexID [[vertex_id]],
    constant SpineVertex *vertices [[buffer(SpineVertexInputIndexVertices)]],
    constant SpineTransform *transform [[buffer(SpineVertexInputIndexTransform)]],
    constant vector_uint2 *viewportSizePointer [[buffer(SpineVertexInputIndexViewportSize)]]
) {
    RasterizerData out;

    simd_float2 pixelSpacePosition = vertices[vertexID].position.xy;
    simd_float2 viewportSize = simd_float2(*viewportSizePointer);

    out.position = simd_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = pixelSpacePosition;
    out.position.xy *= transform->scale;
    out.position.xy += transform->translation * transform->scale + transform->offset;
    out.position.xy /= viewportSize / 2;
    out.position.y *= -1;

    out.color = vertices[vertexID].color;
    out.textureCoordinate = vertices[vertexID].uv;
    out.bleach = vertices[vertexID].bleach;

    return out;
}

fragment simd_float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<half> colorTexture [[texture(SpineTextureIndexBaseColor)]]
) {
    constexpr sampler textureSampler(
        mag_filter::nearest,
        min_filter::nearest
    );

    half4 tex = colorTexture.sample(textureSampler, in.textureCoordinate);

    float amount = clamp(in.bleach, 0.0, 1.0);

    // 标准亮度权重，比直接平均 rgb 更自然
    half luminance = dot(tex.rgb, half3(0.299h, 0.587h, 0.114h));
    half3 grayRgb = half3(luminance);

    // 只处理 texture 本身，不处理 slot tint
    half3 processedTextureRgb = mix(
        tex.rgb,
        grayRgb,
        half(amount)
    );

    simd_float4 outColor;
    outColor.rgb = simd_float3(processedTextureRgb) * in.color.rgb;
    outColor.a = tex.a * in.color.a;

    return outColor;
}
