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
  NSUInteger gpuFamily = [mrc featureSetGPUFamily];

  NSString *sumReduceShader = @"fragmentShaderPrefixSumReduce";
  NSString *sumReduceShaderA7 = @"fragmentShaderPrefixSumReduceA7";
  
  if (gpuFamily == 1) {
    // A7
    sumReduceShader = sumReduceShaderA7;
  }
  
  self.reducePipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                                   pipelineLabel:@"PrefixSumReduce Pipeline"
                                                  numAttachments:1
                                              vertexFunctionName:@"vertexShader"
                                            fragmentFunctionName:sumReduceShader];
  
  NSAssert(self.reducePipelineState, @"reducePipelineState");

  // FIXME: A7 support
  
  NSString *sumSweepShader = @"fragmentShaderPrefixSumDownSweep";
  
  self.sweepPipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                 pipelineLabel:@"PrefixSumSweep Pipeline"
                                numAttachments:1
                            vertexFunctionName:@"vertexShader"
                          fragmentFunctionName:sumSweepShader];
  
  NSAssert(self.sweepPipelineState, @"sweepPipelineState");
  
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
// renderSize : indicates the size of the entire texture containing block by block numbers
// renderFrame : holds textures used while rendering
// blockDimension : indicates the POT dimension, a 4x4 size block is indicated by the value 4

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
               blockDimension:(int)blockDimension
{
  unsigned int width = renderSize.width;
  unsigned int height = renderSize.height;

  const int blockDim = HUFF_BLOCK_DIM;
  
  renderFrame.width = width;
  renderFrame.height = height;
  renderFrame.blockDim = blockDim;
  
  // The number of iterations needed to reduce a blockDimension x blockDimension
  // sized block down to just 1 value (not including the final render to 1 pixel).
  
  int totalNumPixels = (int) (blockDimension * blockDimension);
  
  int numReductions = 0;
  
  for (int i = 0; i < 32; i++) {
    totalNumPixels /= 2;
    if (totalNumPixels == 1) {
      // No reduction down to just 1 pixel is needed
      break;
    }
    numReductions += 1;
  }
  
  NSLog(@"for %d x %d block dimension : numReductions %d", blockDimension, blockDimension, numReductions);
  
  // FIXME: should be provided by caller
  
  // Texture that holds original image order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputImageOrderTexture = txt;
  }

  // Texture that holds block order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputBlockOrderTexture = txt;
  }
  
  // FIXME: pass int recursion depth into reduction and sweep shader (stack on N of these)
  
  renderFrame.reduceTextures = [NSMutableArray array];
  renderFrame.sweepTextures = [NSMutableArray array];
  
  int textureWidth = width;
  int textureHeight = height;
  
  // Create a single output texture at 1/2 the height
  
  int pot = 1;
  
  for (int i = 0; i < numReductions; i++) {
    if (textureWidth == textureHeight) {
      // square texture to rect of 1/2 the width
      textureWidth = textureWidth / 2;
    } else {
      // rect texture to square that is 1/2 the height
      textureHeight = textureHeight / 2;
    }
    
    int reduceStep = i + 1;
    
    NSLog(@"reduction %d : texture %3d x %3d : POT %d", reduceStep, textureWidth, textureHeight, pot);
    
    id<MTLTexture> txt;
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];

    [renderFrame.reduceTextures addObject:txt];
    
    NSLog(@"sweep     %d : texture %3d x %3d : POT %d", reduceStep, textureWidth, textureHeight, pot);
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    [renderFrame.sweepTextures addObject:txt];
    
    // FIXME: allocate target dimension buffer to pass in POT ?
    
    pot *= 2;
  }
  
  // One last texture is uninitialized so it is all zeros
  
  {
    id<MTLTexture> txt;
    
    if (textureWidth == textureHeight) {
      // square texture to rect of 1/2 the width
      textureWidth = textureWidth / 2;
    } else {
      // rect texture to square that is 1/2 the height
      textureHeight = textureHeight / 2;
    }
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageShaderRead];
    
    renderFrame.zeroTexture = txt;
    
    NSLog(@"zeros : texture %d x %d", textureWidth, textureHeight);
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
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
    // Reduce depth=1 output texture
    id<MTLTexture> inputTexture = renderFrame.inputBlockOrderTexture;
    id<MTLTexture> outputTexture = (id<MTLTexture>) renderFrame.reduceTextures[0];
    
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    if (inputTexture.width == inputTexture.height) {
      // reduce square
      assert((inputTexture.width / 2) == outputTexture.width);
      assert(inputTexture.height == outputTexture.height);
    } else {
      // reduce rect
      assert(inputTexture.width == outputTexture.width);
      assert((inputTexture.height / 2) == outputTexture.height);
    }
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG

    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumReduce%d", 1];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.reducePipelineState];
    
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

// Prefix sum sweep, this executes a single sweep step

- (void) renderPrefixSumSweep:(MetalRenderContext*)mrc
                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                inputTexture1:(id<MTLTexture>)inputTexture1
                inputTexture2:(id<MTLTexture>)inputTexture2
                outputTexture:(id<MTLTexture>)outputTexture
{
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
    // FIXME: determine how to grab I/O textures from level argument ?
    
    // Reduce depth=1 output texture
    //id<MTLTexture> inputTexture = renderFrame.inputBlockOrderTexture;
    //id<MTLTexture> outputTexture = (id<MTLTexture>) renderFrame.reduceTextures[0];
    
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    assert(inputTexture2.width == outputTexture.width);
    assert(inputTexture2.height == outputTexture.height);
    
    if (inputTexture1.width == inputTexture1.height) {
      // square
      assert(inputTexture1.width == outputTexture.width);
      assert((inputTexture1.height * 2) == outputTexture.height);
    } else {
      // rect
      assert((inputTexture1.width * 2) == outputTexture.width);
      assert(inputTexture1.height == outputTexture.height);
    }
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG
    
    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumSweep%d", 1];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.sweepPipelineState];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:inputTexture1 atIndex:0];
    [renderEncoder setFragmentTexture:inputTexture2 atIndex:1];
    
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
