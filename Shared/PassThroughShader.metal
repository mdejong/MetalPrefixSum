/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"

// This struct is duplicated from "AAPLShaders.metal" here since implementations
// cannot be directly included due to conflicting symbol names

// Vertex shader outputs and per-fragmeht inputs.  Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment genterated by clip-space primitives.
typedef struct
{
  // The [[position]] attribute qualifier of this member indicates this value is the clip space
  //   position of the vertex wen this structure is returned from the vertex shader
  float4 clipSpacePosition [[position]];
  
  // Since this member does not have a special attribute qualifier, the rasterizer will
  //   interpolate its value with values of other vertices making up the triangle and
  //   pass that interpolated value to the fragment shader for each fragment in that triangle;
  float2 textureCoordinate;
  
} RasterizerData;

// Fragment function
fragment float4
samplingPassThroughFragmentShader(RasterizerData in [[stage_in]],
                                  texture2d<half, access::sample> inTexture [[ texture(AAPLTextureIndexBaseColor) ]])
{
  constexpr sampler s(mag_filter::linear, min_filter::linear);
  
  return float4(inTexture.sample(s, in.textureCoordinate));
}

