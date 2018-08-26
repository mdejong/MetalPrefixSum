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

// Vertex shader outputs and per-fragmeht inputs.  Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment genterated by clip-space primitives.
typedef struct
{
  // The [[position]] attribute qualifier of this member indicates this value is the clip space
  //   position of the vertex when this structure is returned from the vertex shader
  float4 clipSpacePosition [[position]];
  
  // Since this member does not have a special attribute qualifier, the rasterizer will
  //   interpolate its value with values of other vertices making up the triangle and
  //   pass that interpolated value to the fragment shader for each fragment in that triangle;
  float2 textureCoordinate;
  
} PassThroughRasterizerData;

// Vertex Function
vertex PassThroughRasterizerData
samplingPassThroughVertexShader(uint vertexID [[ vertex_id ]],
                                constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]])
{
  PassThroughRasterizerData out;
  
  // Index into our array of positions to get the current vertex
  //   Our positons are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
  //   the origin)
  float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
  
  // THe output position of every vertex shader is in clip space (also known as normalized device
  //   coordinate space, or NDC).   A value of (-1.0, -1.0) in clip-space represents the
  //   lower-left corner of the viewport wheras (1.0, 1.0) represents the upper-right corner of
  //   the viewport.
  
  out.clipSpacePosition.xy = pixelSpacePosition;
  
  // Set the z component of our clip space position 0 (since we're only rendering in
  //   2-Dimensions for this sample)
  out.clipSpacePosition.z = 0.0;
  
  // Set the w component to 1.0 since we don't need a perspective divide, which is also not
  //   necessary when rendering in 2-Dimensions
  out.clipSpacePosition.w = 1.0;
  
  // Pass our input textureCoordinate straight to our output RasterizerData.  This value will be
  //   interpolated with the other textureCoordinate values in the vertices that make up the
  //   triangle.
  out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
  out.textureCoordinate.y = 1.0 - out.textureCoordinate.y;
  
  return out;
}

// Fragment function
fragment float4
samplingPassThroughFragmentShader(PassThroughRasterizerData in [[stage_in]],
                                  texture2d<half, access::sample> inTexture [[ texture(AAPLTextureIndexBaseColor) ]])
{
  constexpr sampler s(mag_filter::linear, min_filter::linear);
  
  return float4(inTexture.sample(s, in.textureCoordinate));
}

