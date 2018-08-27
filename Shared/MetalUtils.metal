/*
See LICENSE folder for this sample’s licensing information.

Abstract:

Utility methods useful in metal shaders
 
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"


// Given coordinates, calculate relative coordinates in a 2d grid
// by applying a block offset. A blockOffset for a 2x2 block
// would be:
//
// [0 1]
// [2 3]

static inline
ushort2 relative_coords(const ushort2 rootCoords, const ushort blockDim, ushort blockOffset)
{
  const ushort dx = blockOffset % blockDim;
  const ushort dy = blockOffset / blockDim;
  return rootCoords + ushort2(dx, dy);
}

// Convert image (X,Y) to a uint offset

static inline
uint coords_to_offset(const ushort width, const ushort2 coords)
{
  uint offset = (uint(coords.y) * width) + coords.x;
  return offset;
}

// Convert image offset stored in a uint to (X,Y)

static inline
ushort2 offset_to_coords(const ushort blockDim, const uint offset)
{
  const ushort dx = offset % blockDim;
  const ushort dy = offset / blockDim;
  return ushort2(dx, dy);
}

// Given a half precision float value that represents a normalized byte, convert
// from floating point to a byte representation and return as a ushort value.

static inline
uint8_t uint8_from_half(const half inHalf)
{
  return uint8_t(round(inHalf * 255.0h));
}

// Convert from uint8_t int to half float

static inline
half uint8_to_half(const uint8_t inByte)
{
  return inByte/255.0h;
}

// Given a half precision float value that represents a normalized byte, convert
// from floating point to a byte representation and return as a ushort value.

static inline
ushort ushort_from_half(const half inHalf)
{
  return ushort(round(inHalf * 255.0h));
}

// Convert from ushort int to half float

static inline
half ushort_to_half(const ushort inByte)
{
  return inByte/255.0h;
}

static inline
uint uint_from_half(const half inHalf)
{
  return uint(ushort_from_half(inHalf));
}

// Given 4 half values that represent normalized float byte values,
// convert each component to a BGRA uint representation

static inline
uint uint_from_half4(const half4 inHalf4)
{
  ushort b = ushort_from_half(inHalf4.b);
  ushort g = ushort_from_half(inHalf4.g);
  ushort r = ushort_from_half(inHalf4.r);
  ushort a = ushort_from_half(inHalf4.a);
  
  ushort c0 = (g << 8) | b;
  ushort c1 = (a << 8) | r;
  
  return (uint(c1) << 16) | uint(c0);
}

// Given a fragment shader coordinate (normalized) calculate an integer "gid" value
// that represents the (X,Y) as a short coordinate pair.

static inline
ushort2 calc_gid_from_frag_norm_coord(const ushort2 dims, const float2 textureCoordinate)
{
  // Convert float coordinates to integer (X,Y) offsets, aka gid
  const float2 textureSize = float2(dims.x, dims.y);
  float2 c = textureCoordinate;
  const float2 halfPixel = (1.0 / textureSize) / 2.0;
  c -= halfPixel;
  ushort2 gid = ushort2(round(c * textureSize));
  return gid;
}

// Decode zigzag encoding, useful when representing negative
// numbers as positive ones. This implementation uses only
// bits operations and it contains no branches.
//
// 0 = 0, -1 = 1, 1 = 2, -2 = 3, 2 = 4, -3 = 5, 3 = 6

// Note that this methods returns an 8 bit
// uint8_t but the value is a signed delta.

static inline
uint8_t
zigzag_offset_to_num_neg(uint8_t value) {
  ushort unValue = value;
  ushort high7Bits = unValue >> 1;
  ushort low1Bits = unValue & 0x1;
  return (int8_t) (high7Bits ^ -low1Bits);
}

