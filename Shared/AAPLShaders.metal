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

#import "MetalUtils.metal"

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

// Vertex Function
vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]])
{
    RasterizerData out;

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

fragment float4
fragmentFillShader2(RasterizerData in [[stage_in]])
{
  return float4(0.0, 1.0 - in.textureCoordinate.y, in.textureCoordinate.y, 1.0);
}

// Fragment function that crops from grayscale 8 bit input texture while rendering
// BGRA grayscale pixels to the output texture.

fragment half4
samplingCropShader(RasterizerData in [[stage_in]],
                   texture2d<half, access::read> inTexture [[ texture(0) ]],
                   constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  const ushort2 renderSize = ushort2(rtd.width, rtd.height);
  ushort2 gid = calc_gid_from_frag_norm_coord(renderSize, in.textureCoordinate);

  // Map gid from image order coords to block by block order
  // by figuring out the offset from block root to this coord
  // and then read from a global offset that is that number
  // of positions from where that block begins.
  
  // uint coords_to_offset(const ushort width, const ushort2 coords)
  // ushort2 offset_to_coords(const ushort blockDim, const uint offset)
  
  const ushort blockDim = 8;
  
  ushort2 blockRoot = gid / blockDim;
  uint blocki = coords_to_offset(blockDim, blockRoot);
  ushort2 blockRootCoords = blockRoot * blockDim;
  ushort2 offsetFromBlockRootCoords = gid - blockRootCoords;
  ushort offsetFromBlockRoot = coords_to_offset(blockDim, offsetFromBlockRootCoords);
  
  uint offsetFromBlockByBlockRoot = (blocki * blockDim * blockDim) + offsetFromBlockRoot;
  ushort2 readCoords = offset_to_coords(rtd.width, offsetFromBlockByBlockRoot);
  
  half value = inTexture.read(readCoords).x;
  half4 outGrayscale = half4(value, value, value, 1.0h);
  return outGrayscale;
}

