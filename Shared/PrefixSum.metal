/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shader logic used for parallel prefix sum operation.
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"

#import "MetalUtils.metal"

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

// Prefix Sum Reduce

// Debug fragment shader that emits prefixBytes as 8 bit output values.
// This shader reads from an input texture and reduces each pair of
// input byte values to a single byte value by adding them together
// with unsigned 8 bit int math.

// fragment shader that reads a N x N block and writes N/2 x N
// pixels to the output texture. The total number of pixels is
// reduced by 2 and the width is cut in half to produce an
// output rect texture that is 2x as tall as it is wide.

// Input 4x4 = 16 pixels (square)
//
// 0  1  2  3
// 4  5  6  7
// 8  9  A  B
// C  D  E  F

// 4x4 -> 2x4 = 8 (rect)

// 01 23 - (0,0) (1,0)
// 45 67 - (0,1) (1,1)
// 89 AB - (0,2) (1,2)
// CD EF - (0,3) (1,3)

// 1x offset (0,0) reads 2x (0,0) and (1,0)
// 1x offset (1,0) reads 2x (2,0) and (3,0)
// 1x offset (0,1) reads 2x (0,1) and (1,1)
// 1x offset (1,1) reads 2x (2,1) and (3,1)

// 2x4 -> 2x2 = 4 (square)

// 0123 4567 - (0,0) (1,0)
// 89AB CDEF - (0,1) (1,1)

// 1x offset (0,0) reads 2x (0,0) and (1,0)
// 1x offset (1,0) reads 2x (0,1) and (1,1)

// 1x offset (0,1) reads 2x (0,2) and (1,2)
// 1x offset (1,1) reads 2x (0,3) and (1,3)

// 2x2 -> 1x2 = 2 (rect)

// 01234567
// 89ABCDEF

// nop down to 1x1 since results not used

// 2x1 -> 1x1 = 1 (square)

// 0123456789ABCDEF

// FIXME: remove rtd arguent if blockSize is not needed for calc_gid_from_frag_norm_coord()

fragment half
fragmentShaderPrefixSumReduce(RasterizerData in [[stage_in]],
                              texture2d<half, access::read> inTexture [[ texture(0) ]],
                              constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  ushort2 renderSize;
  
  // FIXME: pass output render size in rtd ?
  
  if (inTexture.get_width() == inTexture.get_height()) {
    // Reduce Square
    renderSize = ushort2(inTexture.get_width() / 2, inTexture.get_height());
  } else {
    // Reduce Rect
    renderSize = ushort2(inTexture.get_width(), inTexture.get_height() / 2);
  }
  
  ushort2 gid = calc_gid_from_frag_norm_coord(renderSize, in.textureCoordinate);
  
  uint gidOffset1 = coords_to_offset(renderSize.x, gid);
  gidOffset1 *= 2;

  uint gidOffset2 = gidOffset1 + 1;
  
  // Convert to (X,Y) coords in terms of input width
  ushort2 b1Coords = offset_to_coords(inTexture.get_width(), gidOffset1);
  ushort2 b2Coords = offset_to_coords(inTexture.get_width(), gidOffset2);
  
  uint8_t b1 = uint8_from_half(inTexture.read(b1Coords).x);
  uint8_t b2 = uint8_from_half(inTexture.read(b2Coords).x);
  
  // width of render texture
  //return uint8_to_half(renderSize.x);
  // height of render texture
  //return uint8_to_half(renderSize.y);
  
  // return just the first value read
  //return uint8_to_half(b1);
  // return just the second value read
  //return uint8_to_half(b2);
  
  // This logic is known to optimize properly
  // on newer than A7 devices but it fails on A7
  
  return uint8_to_half(b1 + b2);
}

// Same logic as shader above with workaround specific to A7
// related to converting the sum of 2 reads to byte and then back to float.

fragment half
fragmentShaderPrefixSumReduceA7(RasterizerData in [[stage_in]],
                                texture2d<half, access::read> inTexture [[ texture(0) ]],
                                constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  ushort2 renderSize;
  
  if (inTexture.get_width() == inTexture.get_height()) {
    // Reduce Square
    renderSize = ushort2(inTexture.get_width() / 2, inTexture.get_height());
  } else {
    // Reduce Rect
    renderSize = ushort2(inTexture.get_width(), inTexture.get_height() / 2);
  }
  
  ushort2 gid = calc_gid_from_frag_norm_coord(renderSize, in.textureCoordinate);
  
  uint gidOffset1 = coords_to_offset(renderSize.x, gid);
  gidOffset1 *= 2;
  
  uint gidOffset2 = gidOffset1 + 1;
  
  // Convert to (X,Y) coords in terms of input width
  ushort2 b1Coords = offset_to_coords(inTexture.get_width(), gidOffset1);
  ushort2 b2Coords = offset_to_coords(inTexture.get_width(), gidOffset2);
  
  uint8_t b1 = uint8_from_half(inTexture.read(b1Coords).x);
  uint8_t b2 = uint8_from_half(inTexture.read(b2Coords).x);
  
  // width of render texture
  //return uint8_to_half(renderSize.x);
  // height of render texture
  //return uint8_to_half(renderSize.y);
  
  // return just the first value read
  //return uint8_to_half(b1);
  // return just the second value read
  //return uint8_to_half(b2);
  
  // This should work properly on A7 but it does not
  
  //return uint8_to_half(b1 + b2);
  
  // This should work properly on A7 but it does not
  
  // uint8_t sum = b1 + b2;
  // return half(ushort(sum) / 255.0h);
  
  // This does work properly on A7, note the
  // literal here is a float value not a half float.
  uint8_t sum = b1 + b2;
  return half(ushort(sum) / 255.0);
}

/*
 
// fragment shader that reads a N/2 x N block and writes a N/2 x N/2
// pixels to the output texture.

fragment half
fragmentShaderPrefixSumReduceRect(RasterizerData in [[stage_in]],
                                  texture2d<half, access::read> inTexture [[ texture(0) ]],
                                  constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  // 4x4 -> 2x4 = 8 (rect)
  
  // 01 23 - (0,0) (1,0)
  // 45 67 - (0,1) (1,1)
  // 89 AB - (0,2) (1,2)
  // CD EF - (0,3) (1,3)
  
  // 2x4 -> 2x2 = 4 (square)
  
  // 0123 4567 - (0,0) (1,0)
  // 89AB CDEF - (0,1) (1,1)
  
  // 1x offset (0,0) reads 2x (0,0) and (1,0)
  // 1x offset (1,0) reads 2x (0,1) and (1,1)
  
  // 1x offset (0,1) reads 2x (0,2) and (1,2)
  // 1x offset (1,1) reads 2x (0,3) and (1,3)
  
  const ushort2 renderSize = ushort2(inTexture.get_width(), inTexture.get_height() / 2);
  ushort2 gid = calc_gid_from_frag_norm_coord(renderSize, in.textureCoordinate);
  gid.y *= 2;
  
  ushort isOdd = (gid.x & 0x1);
  gid.x -= isOdd;
  gid.y += isOdd;
  
  ushort2 gid2 = gid;
  gid2.x += 1;
  
  uint8_t b1 = uint8_from_half(inTexture.read(gid).x);
  uint8_t b2 = uint8_from_half(inTexture.read(gid2).x);
  
  // width of render texture
  //return uint8_to_half(renderSize.x);
  // height of render texture
  //return uint8_to_half(renderSize.y);
  
  // return just the first value read
  //return uint8_to_half(b1);
  // return just the second value read
  //return uint8_to_half(b2);
  
  return uint8_to_half(b1 + b2);
}

 */

