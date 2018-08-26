//
//  MetalPrefixSumRenderContext.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object Metal references that are associated with a
//  rendering context like a view but are not defined on a
//  render frame. There is 1 render contet for N render frames.

#include "MetalPrefixSumRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"
#import "MetalPrefixSumRenderFrame.h"

// Private API

@interface MetalPrefixSumRenderContext ()

//@property (readonly) size_t numBytesAllocated;

@end

// Main class performing the rendering
@implementation MetalPrefixSumRenderContext

// Setup render pixpelines

- (void) setupRenderPipelines:(MetalRenderContext*)mrc
{
  self.reduceSquarePipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                                   pipelineLabel:@"PrefixSumReduce Square Pipeline"
                                                  numAttachments:1
                                              vertexFunctionName:@"vertexShader"
                                            fragmentFunctionName:@"fragmentShaderPrefixSumReduceSquare"];
  
  NSAssert(self.reduceSquarePipelineState, @"reduceSquarePipelineState");
  
#if defined(DEBUG)
  
  // Debug render state to emit (X,Y) for each pixel of render texture
  
//  self.debugRenderXYoffsetTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
//                                                          pipelineLabel:@"Render To XY Pipeline"
//                                                         numAttachments:1
//                                                     vertexFunctionName:@"vertexShader"
//                                                   fragmentFunctionName:@"samplingShaderDebugOutXYCoordinates"];
  
#endif // DEBUG
}

// Render textures initialization

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  unsigned int width = renderSize.width;
  unsigned int height = renderSize.height;

  const int blockDim = HUFF_BLOCK_DIM;
  
//  unsigned int width = renderFrame.width;
//  unsigned int height = renderFrame.height;
  
  /*
  const int blockDim = HUFF_BLOCK_DIM;
  
  unsigned int width = renderSize.width;
  unsigned int height = renderSize.height;
  
  assert(width > 0);
  assert(height > 0);
  
  unsigned int blockWidth = width / blockDim;
  if ((width % blockDim) != 0) {
    blockWidth += 1;
  }
  
  unsigned int blockHeight = height / blockDim;
  if ((height % blockDim) != 0) {
    blockHeight += 1;
  }
  
  assert(blockWidth > 0);
  assert(blockHeight > 0);
  
  renderFrame.blockWidth = blockWidth;
  renderFrame.blockHeight = blockHeight;
   
  */
  
  renderFrame.width = width;
  renderFrame.height = height;
  renderFrame.blockDim = blockDim;
  
  // FIXME: should be provided by caller
  
  // Texture that holds original image order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputImageOrderTexture = txt;
  }

  // Texture that holds block order input bytes
  
  {
    assert(width == 4);
    assert(height == 4);
    
    uint8_t prefixSumBytes[] = {
      0,   1,  2,  3,
      4,   5,  6,  7,
      8,   9, 10, 11,
      12, 13, 14, 15
    };
    
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:prefixSumBytes usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputBlockOrderTexture = txt;
  }
  
  // FIXME: pass int recursion depth into reduction and sweep shader (stack on N of these)
  
  renderFrame.reduceTextures = [NSMutableArray array];
  renderFrame.sweepTextures = [NSMutableArray array];
  
  // Create a single output texture at 1/2 the height
  
  for (int i = 0; i < 1; i++) {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width/2, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];

    [renderFrame.reduceTextures addObject:txt];
  }
  
  // Dimensions passed into shaders
  
  renderFrame.renderTargetDimensionsAndBlockDimensionsUniform = [mrc.device newBufferWithLength:sizeof(RenderTargetDimensionsAndBlockDimensionsUniform) options:MTLResourceStorageModeShared];
  
  {
    RenderTargetDimensionsAndBlockDimensionsUniform *ptr = renderFrame.renderTargetDimensionsAndBlockDimensionsUniform.contents;
    ptr->width = width;
    ptr->height = height;
    ptr->blockWidth = width;
    ptr->blockHeight = height;
  }
  
  // For each block, there is one 32 bit number that stores the next bit
  // offset into the huffman code buffer. Each successful code write operation
  // will read from 1 to 16 bits and increment the counter for a specific block.
  
//  renderFrame.blockStartBitOffsets = [_device newBufferWithLength:sizeof(uint32_t)*(blockWidth*blockHeight)
//                                                          options:MTLResourceStorageModeShared];
  
  /*
  
  // Zero out pixels / set to known init state
  
  if ((1))
  {
    int numBytes = (int) (renderFrame.render12Zeros.width * renderFrame.render12Zeros.height * sizeof(uint32_t));
    uint32_t *pixels = malloc(numBytes);
    
    // Init all lanes to zero
    memset(pixels, 0, numBytes);
    
    {
      NSUInteger bytesPerRow = renderFrame.render12Zeros.width * sizeof(uint32_t);
      
      MTLRegion region = {
        { 0, 0, 0 },                   // MTLOrigin
        {renderFrame.render12Zeros.width, renderFrame.render12Zeros.height, 1} // MTLSize
      };
      
      // Copy the bytes from our data object into the texture
      [renderFrame.render12Zeros replaceRegion:region
                        mipmapLevel:0
                          withBytes:pixels
                        bytesPerRow:bytesPerRow];
    }
    
    free(pixels);
  }
   
  */
  
  return;
}

#if defined(DEBUG)

/*

// Implements debug render operation where (X,Y) values are written to a buffer

- (void) debugRenderXYToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  // Debug render XY values out as 2 12 bit values
  
  MTLRenderPassDescriptor *debugRenderXYToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(debugRenderXYToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.debugRenderXYoffsetTexture;
    
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:debugRenderXYToTexturePassDescriptor];
    renderEncoder.label = @"debugRenderToXYCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"debugRenderToXY"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.debugRenderXYoffsetTexturePipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.indexesTexture
                              atIndex:AAPLTextureIndexes];
    [renderEncoder setFragmentTexture:renderFrame.lutiOffsetsTexture
                              atIndex:AAPLTextureLutOffsets];
    [renderEncoder setFragmentTexture:renderFrame.lutsTexture
                              atIndex:AAPLTextureLuts];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // debugRenderToIndexes
    
    [renderEncoder endEncoding];
  }
}

*/

#endif // DEBUG

// Prefix sum render operation, this executes a single reduce step

- (void) renderPrefixSumReduce:(MetalRenderContext*)mrc
                 commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
    // Reduce depth=1 output texture
    id<MTLTexture> inputTexture = renderFrame.inputBlockOrderTexture;
    id<MTLTexture> outputTexture = (id<MTLTexture>) renderFrame.reduceTextures[0];
    
#if defined(DEBUG)
    // Output should be 1/2 the width of input
    assert((inputTexture.width / 2) == outputTexture.width);
    assert(inputTexture.height == outputTexture.height);
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"PrefixSumReduceD1";
    
    [renderEncoder pushDebugGroup: @"PrefixSumReduceD1"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.reduceSquarePipelineState];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.inputBlockOrderTexture atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:mrc.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

@end
