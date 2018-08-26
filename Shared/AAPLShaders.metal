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
    //   position of the vertex wen this structure is returned from the vertex shader
    float4 clipSpacePosition [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer will
    //   interpolate its value with values of other vertices making up the triangle and
    //   pass that interpolated value to the fragment shader for each fragment in that triangle;
    float2 textureCoordinate;

} RasterizerData;

typedef struct {
  uint8_t symbol;
  uint8_t bitWidth;
} VariableBitWidthSymbol;

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

// Fill texture with gradient from green to blue as Y axis increases from origin at top left

fragment float4
fragmentFillShader1(RasterizerData in [[stage_in]],
                   float4 framebuffer [[color(0)]])
{
  return float4(0.0, (1.0 - in.textureCoordinate.y) * framebuffer.x, in.textureCoordinate.y * framebuffer.x, 1.0);
}

fragment float4
fragmentFillShader2(RasterizerData in [[stage_in]])
{
  return float4(0.0, 1.0 - in.textureCoordinate.y, in.textureCoordinate.y, 1.0);
}

// Fragment function
fragment float4
samplingPassThroughShader(RasterizerData in [[stage_in]],
               texture2d<half, access::sample> inTexture [[ texture(AAPLTextureIndexes) ]])
{
  constexpr sampler s(mag_filter::linear, min_filter::linear);
  
  return float4(inTexture.sample(s, in.textureCoordinate));
  
}

// Fragment function that crops from the input texture while rendering
// pixels to the output texture.

fragment half4
samplingCropShader(RasterizerData in [[stage_in]],
                   texture2d<half, access::read> inTexture [[ texture(0) ]],
                   constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  // Convert float coordinates to integer (X,Y) offsets
  const float2 textureSize = float2(rtd.width, rtd.height);
  float2 c = in.textureCoordinate;
  const float2 halfPixel = (1.0 / textureSize) / 2.0;
  c -= halfPixel;
  ushort2 iCoordinates = ushort2(round(c * textureSize));
  
  half value = inTexture.read(iCoordinates).x;
  half4 outGrayscale = half4(value, value, value, 1.0h);
  return outGrayscale;
}

/*
// Single byte clz table implementation with
// special case for clz(0) -> 8 to support
// 9 bit maximum value with 8 bit input.

constant
static
uint8_t clz_byte[256] = {
    8, 7, 6, 6, 5, 5, 5, 5,
    4, 4, 4, 4, 4, 4, 4, 4,
    3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
};

ushort
clz4Byte(uint8_t byteVal)
{
    return clz_byte[byteVal];
}
*/

// A single symbol decode step

VariableBitWidthSymbol
eliasgDecodeSymbol(
                 const device uint8_t *bitBuff,
                 const uint currentNumBits)
{
  const ushort numBitsInByte = 8;
  int numBytesRead = int(currentNumBits / numBitsInByte);
  ushort numBitsReadMod8 = (currentNumBits % numBitsInByte);
  
  ushort inputBitPattern = 0;
  ushort b0 = bitBuff[numBytesRead];
  ushort b1 = bitBuff[numBytesRead+1];
  ushort b2 = bitBuff[numBytesRead+2];
  
  // Left shift the already consumed bits off left side of b0
  b0 <<= numBitsReadMod8;
  b0 &= 0xFF;
  inputBitPattern = b0 << 8;
  
  // Left shift the 8 bits in b1 then OR into inputBitPattern
  inputBitPattern |= b1 << numBitsReadMod8;
  
  // Right shift b2 to throw out unused bits
  b2 >>= (8 - numBitsReadMod8);
  inputBitPattern |= b2;

  // clz on 16 bit register
  //ushort countOfZeros = clz(inputBitPattern);

  // clz on 8 bit value
  ushort countOfZeros = clz(uint8_t(inputBitPattern >> 8));

  // 8 bit clz lookup table
  //ushort countOfZeros = clz4Byte(uint8_t(inputBitPattern >> 8));
    
  // Shift left to place MSB of symbol at the MSB of 16 bit register
  ushort shiftedLeft = inputBitPattern << countOfZeros;
  
  // Shift right to place MSB of value at correct bit offset
  ushort shiftedRight = shiftedLeft >> (16 - (countOfZeros+1));

  VariableBitWidthSymbol vws;
  vws.symbol = (shiftedRight - 1);;
  vws.bitWidth = ((countOfZeros << 1) + 1); // ((countOfZeros * 2) + 1);
  
  return vws;
}

// Given coordinates, calculate relative coordinates in a 2d grid
// by applying a block offset. A blockOffset for a 2x2 block
// would be:
//
// [0 1]
// [2 3]

ushort2 relative_coords(const ushort2 rootCoords, const ushort blockDim, ushort blockOffset)
{
  const ushort dx = blockOffset % blockDim;
  const ushort dy = blockOffset / blockDim;
  return rootCoords + ushort2(dx, dy);
}

// Given a half precision float value that represents a normalized byte, convert
// from floating point to a byte representation and return as a ushort value.

ushort ushort_from_half(const half inHalf)
{
  return ushort(round(inHalf * 255.0h));
}

uint uint_from_half(const half inHalf)
{
  return uint(ushort_from_half(inHalf));
}

// Given 4 half values that represent normalized float byte values,
// convert each component to a BGRA uint representation

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

// FIXME: faster to calc based on constant half pixel already as float?

// Given a fragment shader coordinate (normalized) calculate an integer "gid" value
// that represents the (X,Y) as a short coordinate pair.

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

//int32_t
//offset_to_num_neg(uint32_t value) {
//    if (value == 0) {
//        return value;
//    } else if ((value & 0x1) != 0) {
//        // odd numbers are negative values
//        return ((int)value + 1) / -2;
//    } else {
//        return value / 2;
//    }
//}

// branchless version

ushort
offset_to_num_neg(ushort value) {
    ushort oneIfOddZeroIfEven = (value & 0x1);
    // case 0    : val
    // case even : (value / 2);
    // case odd  : ((value+1) / 2)
    ushort valDiv2 = (value + oneIfOddZeroIfEven) >> 1;
    // even = 1 - 0 - 0 = 1
    // odd  = 1 - 1 - 1 = -1
    short negOneIfOddOneIfEven = 1 - oneIfOddZeroIfEven - oneIfOddZeroIfEven;
    // Represent as unsigned byte
    return ushort(valDiv2 * negOneIfOddOneIfEven);
}

// This function implements a single step of a huffman symbol decode operation

half decode_one_eliasg_symbol(
                                 const uint numBitsReadForBlockRoot,
                                 thread ushort & numBitsRead,
                                 thread ushort & prevSymbol,
                                 const device uint8_t *bitBuff)
{
  uint currentNumBits = numBitsReadForBlockRoot + numBitsRead;
  
  // Lookup 16 bit symbol in left justified table
  
  VariableBitWidthSymbol vws = eliasgDecodeSymbol(
                                                  bitBuff,
                                                  currentNumBits);
  numBitsRead += vws.bitWidth;
  
  ushort outSymbol = (prevSymbol + offset_to_num_neg(vws.symbol)) & 0xFF;
  prevSymbol = outSymbol;
  
  return outSymbol/255.0h;
}

// A 12 symbol huff render stage will map a single output pixel
// (X,Y) location to 12 byte symbols in 3 BGRA pixels. This
// shader will need to be invoked 4 times to render 48 pixels.

struct FragmentOutput12 {
  half4 c0 [[ color(0) ]];
  half4 c1 [[ color(1) ]];
  half4 c2 [[ color(2) ]];
  half4 numBitsRead [[ color(3) ]];
};

// A 16 symbol huff render stage will map a single output pixel
// (X,Y) location to 16 byte symbols.

struct FragmentOutput16 {
  half4 c0 [[ color(0) ]];
  half4 c1 [[ color(1) ]];
  half4 c2 [[ color(2) ]];
  half4 c3 [[ color(3) ]];
};

fragment FragmentOutput12
fragmentShaderB8W12(RasterizerData in [[stage_in]],
                        texture2d<half, access::read> inBitsReadTexture  [[texture(0)]],
                        const device uint32_t *blockStartBitOffsetsPtr [[ buffer(0) ]],
                        const device uint8_t *bitBuff [[ buffer(1) ]],
                        constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(2) ]]
                        )
{
  const ushort numWholeBlocksInWidth = rtd.blockWidth;
  ushort2 gid = calc_gid_from_frag_norm_coord(ushort2(rtd.blockWidth, rtd.blockHeight), in.textureCoordinate);

  FragmentOutput12 fragOut;
  
  // Calculate blocki in terms of the number of whole blocks in the output texture
  // where each pixel corresponds to one block.
  
  const int blocki = (int(gid.y) * numWholeBlocksInWidth) + gid.x;
  
  // Lookup the starting number of bits offset for each pixel in this block

  half4 bitsRead4 = inBitsReadTexture.read(gid);
  ushort2 bitsReadInt2 = ushort2(round(bitsRead4.b * 255.0h), round(bitsRead4.g * 255.0h));
  ushort bitsReadPrev = (bitsReadInt2.y << 8) | bitsReadInt2.x;
  
  const uint numBitsReadForBlockRoot = blockStartBitOffsetsPtr[blocki];
  
  // Init running bit counter for the block
  
  ushort numBitsRead = bitsReadPrev;
  
  ushort prevSymbol = round(bitsRead4.r  * 255.0h);
  
  half4 hc;
  
  // renderStep = 0,1,2,3
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c0 = hc;
  
  // renderStep = 4,5,6,7
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c1 = hc;

  // renderStep = 8,9,10,11
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);

  fragOut.c2 = hc;

  // Emit 16 bit numBitsRead in BG components
  // Emit 8 bit prev symbol value in R component
  
  hc = half4(prevSymbol/255.0h, ((numBitsRead >> 8) & 0xFF)/255.0h, (numBitsRead & 0xFF)/255.0h, 1.0h);
  
  fragOut.numBitsRead = hc;
  
  return fragOut;
}

fragment FragmentOutput16
fragmentShaderB8W16(RasterizerData in [[stage_in]],
                        texture2d<half, access::read> inBitsReadTexture  [[texture(0)]],
                        const device uint32_t *blockStartBitOffsetsPtr [[ buffer(0) ]],
                        const device uint8_t *bitBuff [[ buffer(1) ]],
                        constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(2) ]]
                        )
{
  const ushort numWholeBlocksInWidth = rtd.blockWidth;
  ushort2 gid = calc_gid_from_frag_norm_coord(ushort2(rtd.blockWidth, rtd.blockHeight), in.textureCoordinate);
  
  FragmentOutput16 fragOut;
  
  // Calculate blocki in terms of the number of whole blocks in the output texture
  // where each pixel corresponds to one block.
  
  const int blocki = (int(gid.y) * numWholeBlocksInWidth) + gid.x;
  
  // Lookup the starting number of bits offset for each pixel in this block
  
  half4 bitsRead4 = inBitsReadTexture.read(gid);
  ushort2 bitsReadInt2 = ushort2(round(bitsRead4.b * 255.0h), round(bitsRead4.g * 255.0h));
  ushort bitsReadPrev = (bitsReadInt2.y << 8) | bitsReadInt2.x;
  
  const uint numBitsReadForBlockRoot = blockStartBitOffsetsPtr[blocki];
  
  // Init running bit counter for the block
  
  ushort numBitsRead = bitsReadPrev;
  
  ushort prevSymbol = round(bitsRead4.r  * 255.0h);
  
  half4 hc;
  
  // renderStep = 0,1,2,3
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c0 = hc;
  
  // renderStep = 4,5,6,7
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c1 = hc;
  
  // renderStep = 8,9,10,11
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c2 = hc;

  // renderStep = 12,13,14,15
  
  hc.b = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.g = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.r = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  hc.a = decode_one_eliasg_symbol(numBitsReadForBlockRoot, numBitsRead, prevSymbol, bitBuff);
  
  fragOut.c3 = hc;
  
  // Note that numBitsRead and prevSymbol are not stored by this shader
  
  return fragOut;
}

// Read pixels from multiple textures and zip results back together

fragment half4
cropAndGrayscaleFromTexturesFragmentShader(RasterizerData in [[stage_in]],
                                           texture2d<half, access::read> inTexture [[ texture(0) ]],
                                           constant RenderTargetDimensionsAndBlockDimensionsUniform & rtd [[ buffer(0) ]])
{
  const ushort blockDim = HUFF_BLOCK_DIM;
  
  ushort2 gid = calc_gid_from_frag_norm_coord(ushort2(rtd.width, rtd.height), in.textureCoordinate);
  
  // Calculate blocki in terms of the number of whole blocks in the input texture.
  
  ushort2 blockRoot = gid / blockDim;
  ushort2 blockRootCoords = blockRoot * blockDim;
  ushort2 offsetFromBlockRootCoords = gid - blockRootCoords;
  ushort offsetFromBlockRoot = (offsetFromBlockRootCoords.y * blockDim) + offsetFromBlockRootCoords.x;
  ushort slice = (offsetFromBlockRoot / 4) % 16;

  const ushort blockWidth = rtd.blockWidth;
  const ushort blockHeight = rtd.blockHeight;
  const ushort maxNumBlocksInColumn = 8;
  ushort2 sliceCoord = ushort2(slice % maxNumBlocksInColumn, slice / maxNumBlocksInColumn);
  
  ushort2 inCoords = blockRoot + ushort2(sliceCoord.x * blockWidth, sliceCoord.y * blockHeight);
  half4 inHalf4 = inTexture.read(inCoords);
  
  // For (0, 1, 2, 3, 0, 1, 2, 3, ...) choose (R, G, B, A)
  
  ushort remXOf4 = offsetFromBlockRoot % 4;
  
//  This logic shows a range bug on A7
//  half4 reorder4 = half4(inHalf4.b, inHalf4.g, inHalf4.r, inHalf4.a);
//  uint bgraPixel = pack_half_to_unorm4x8(reorder4);
//  ushort bValue = (bgraPixel >> (remXOf4 * 8)) & 0xFF;
//  half value = bValue / 255.0h;

  //  This logic shows a range bug on A7
//  uint bgraPixel = uint_from_half4(inHalf4);
//  ushort bValue = (bgraPixel >> (remXOf4 * 8)) & 0xFF;
//  //half value = bValue / 255.0h;
//  return half4(bValue / 255.0h, bValue / 255.0h, bValue / 255.0h, 1.0h);

  // On A7, this array assign logic does not seem to have the bug and it
  // is faster than the if below.
  
  half hArr4[4];
  hArr4[0] = inHalf4.b;
  hArr4[1] = inHalf4.g;
  hArr4[2] = inHalf4.r;
  hArr4[3] = inHalf4.a;
  half value = hArr4[remXOf4];
  
  // This works and does not show the conversion bug, but seems slower than the array impl

  /*
  half value;

  if (remXOf4 == 0) {
    value = inHalf4.b;
  } else if (remXOf4 == 1) {
    value = inHalf4.g;
  } else if (remXOf4 == 2) {
    value = inHalf4.r;
  } else {
    value = inHalf4.a;
  }
  */
  
  half4 outGrayscale = half4(value, value, value, 1.0h);
  return outGrayscale;
}
