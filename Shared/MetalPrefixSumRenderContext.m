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
  
  NSString *sumSweepShader = @"fragmentShaderPrefixSumDownSweep";
  NSString *sumSweepShaderA7 = @"fragmentShaderPrefixSumDownSweepA7";

  NSString *sumInclusiveSweepShader = @"fragmentShaderPrefixSumInclusiveDownSweep";
  NSString *sumInclusiveSweepShaderA7 = @"fragmentShaderPrefixSumInclusiveDownSweepA7";
  
  if (gpuFamily == 1) {
    // A7
    sumReduceShader = sumReduceShaderA7;
    sumSweepShader = sumSweepShaderA7;
    sumInclusiveSweepShader = sumInclusiveSweepShaderA7;
  }
  
  self.reducePipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                                   pipelineLabel:@"PrefixSumReduce Pipeline"
                                                  numAttachments:1
                                              vertexFunctionName:@"vertexShader"
                                            fragmentFunctionName:sumReduceShader];
  
  NSAssert(self.reducePipelineState, @"reducePipelineState");
  
  self.sweepPipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                 pipelineLabel:@"PrefixSumSweep Pipeline"
                                numAttachments:1
                            vertexFunctionName:@"vertexShader"
                          fragmentFunctionName:sumSweepShader];
  
  NSAssert(self.sweepPipelineState, @"sweepPipelineState");

  self.inclusiveSweepPipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                pipelineLabel:@"PrefixSumInclusiveSweep Pipeline"
                               numAttachments:1
                           vertexFunctionName:@"vertexShader"
                         fragmentFunctionName:sumInclusiveSweepShader];
  
  NSAssert(self.inclusiveSweepPipelineState, @"inclusiveSweepPipelineState");
}

// Render textures initialization
// renderSize : indicates the size of the entire texture containing block by block values
// blockSize  : indicates the size of the block to be summed
// renderFrame : holds textures used while rendering

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                   blockSize:(CGSize)blockSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  const BOOL debug = FALSE;
  
  unsigned int width = renderSize.width;
  unsigned int height = renderSize.height;

  unsigned int blockWidth = blockSize.width;
  unsigned int blockHeight = blockSize.height;
  
  renderFrame.width = width;
  renderFrame.height = height;
  
  // blockDim is the number of elements in a processing block.
  // For example, a 2x2 block has a blockDim of 4 while
  // a 2x4 block has a blockDim of 8. A blockDim is known to
  // be a POT, so it can be treated as such in shader code.
  
  unsigned int blockDim = blockSize.width * blockSize.height;
  
  assert(blockDim > 1);
  BOOL isPOT = (blockDim & (blockDim - 1)) == 0;
  assert(isPOT);
  
  renderFrame.blockDim = blockDim;
  
  // Determine the number of blocks in the input image width
  // along with the number of blocks in the height. The input
  // image need not be a square.
  
#if defined(DEBUG)
  assert((width % blockWidth) == 0);
  assert((height % blockHeight) == 0);
#endif // DEBUG
  
  unsigned int numBlocksInWidth = width / blockWidth;
  unsigned int numBlocksInHeight = height / blockHeight;
  
  renderFrame.numBlocksInWidth = numBlocksInWidth;
  renderFrame.numBlocksInHeight = numBlocksInHeight;
  
  // The number of flat blocks that fits into (width * height) is
  // constant while the texture dimension is being reduced.
  
#if defined(DEBUG)
  assert(((width * height) % blockDim) == 0);
  unsigned int numBlocksInImage = (width * height) / blockDim;
  assert(numBlocksInImage == (numBlocksInWidth * numBlocksInHeight));
#endif // DEBUG
  
  // Texture that holds block order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputBlockOrderTexture = txt;
    
    if (debug) {
      NSLog(@"input       : texture %3d x %3d", (int)txt.width, (int)txt.height);
    }
  }

  // Texture that holds block order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.outputBlockOrderTexture = txt;
    
    if (debug) {
      NSLog(@"output      : texture %3d x %3d", (int)txt.width, (int)txt.height);
    }
  }
  
  // FIXME: pass int recursion depth into reduction and sweep shader (stack on N of these)
  
  renderFrame.reduceTextures = [NSMutableArray array];
  renderFrame.sweepTextures = [NSMutableArray array];
  
  // For each reduction step, the output number of pixels is 1/2 the input
  
  int pot = 1;
  
  const int maxNumReductions = log2(4096);
  
  int reducedBlockWidth = blockWidth;
  int reducedBlockHeight = blockHeight;
  
  if (debug) {
    NSLog(@"block  texture %3d x %3d", reducedBlockWidth, reducedBlockHeight);
  }
  
  unsigned int actualWidth = width;
  unsigned int actualHeight = height;
  
  for (int i = 0; i < maxNumReductions; i++) {
    if (reducedBlockWidth == reducedBlockHeight) {
      // square texture to rect of 1/2 the width
#if defined(DEBUG)
      assert(reducedBlockWidth > 1);
#endif // DEBUG
      reducedBlockWidth /= 2;
    } else {
      // rect texture to square that is 1/2 the height
#if defined(DEBUG)
      assert(reducedBlockHeight > 1);
#endif // DEBUG
      reducedBlockHeight /= 2;
    }
    
    // Calculate actualWidth x actualHeight based on block dimensions.
    // Note the edge case where an input block like 2x2 (POT = 4)
    // would get reduced to 1x2 in the first reduction step, if
    // the input texture size is 
    
    // In an edge case like 2x2 being reduced to 1x2, the width of
    // the output texture would be 1
    
    actualWidth = reducedBlockWidth * numBlocksInWidth;
    actualHeight = reducedBlockHeight * numBlocksInHeight;
    
    if (reducedBlockWidth == 1 && reducedBlockHeight == 1) {
      break;
    }
    
    int reduceStep = i + 1;
    
    if (debug) {
      NSLog(@"reduction/sweep %d : POT %d", reduceStep, pot);
      NSLog(@"block  texture %3d x %3d", reducedBlockWidth, reducedBlockHeight);
      NSLog(@"actual texture %3d x %3d", actualWidth, actualHeight);
    }
    
    id<MTLTexture> txt;
    
    txt = [mrc make8bitTexture:CGSizeMake(actualWidth, actualHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];

    [renderFrame.reduceTextures addObject:txt];
    
    txt = [mrc make8bitTexture:CGSizeMake(actualWidth, actualHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    [renderFrame.sweepTextures addObject:txt];
    
    pot *= 2;
  }
  
  // One last texture is uninitialized so it is all zeros
  
  {
    id<MTLTexture> txt;
    
    // The reductions above must have generated a block width of 1x1
    assert(reducedBlockWidth == 1);
    assert(reducedBlockHeight == 1);
    
    txt = [mrc make8bitTexture:CGSizeMake(actualWidth, actualHeight) bytes:NULL usage:MTLTextureUsageShaderRead];
    
    renderFrame.zeroTexture = txt;
    
    if (debug) {
    NSLog(@"zeros : texture %d x %d", actualWidth, actualHeight);
    }
  }
  
  // Dimensions passed into shaders
  
  renderFrame.renderTargetDimensionsAndBlockDimensionsUniform = [mrc.device newBufferWithLength:sizeof(RenderTargetDimensionsAndBlockDimensionsUniform) options:MTLResourceStorageModeShared];
  
  {
    RenderTargetDimensionsAndBlockDimensionsUniform *ptr = renderFrame.renderTargetDimensionsAndBlockDimensionsUniform.contents;
    // pass numBlocksInWidth
    ptr->width = renderFrame.numBlocksInWidth;
    // pass numBlocksInHeight
    ptr->height = renderFrame.numBlocksInHeight;
    // pass (blockSide * blockSide) as a POT
    ptr->blockWidth = renderFrame.blockDim;
    ptr->blockHeight = renderFrame.blockDim;
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

// FIXME: no reason to pass render frame to these methods since they accept textures directly

- (void) renderPrefixSumReduce:(MetalRenderContext*)mrc
                 commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                  inputTexture:(id<MTLTexture>)inputTexture
                 outputTexture:(id<MTLTexture>)outputTexture
          sameDimTargetTexture:(id<MTLTexture>)sameDimTargetTexture
                         level:(int)level
{
  const BOOL debug = FALSE;
  
  if (debug) {
    NSLog(@"renderPrefixSumReduce inputTexture: %4d x %4d and outputTexture: %4d x %4d at level %d", (int)inputTexture.width, (int)inputTexture.height, (int)outputTexture.width, (int)outputTexture.height, level);
  }
  
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    // In either case, the number of pixels in the render output must be 1/2
    
    int inputNumPixels = (int)inputTexture.width * (int)inputTexture.height;
    int outputNumPixels = (int)outputTexture.width * (int)outputTexture.height;
    
    assert(inputNumPixels == (outputNumPixels * 2));
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG

    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumReduce%d", level];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.reducePipelineState];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:inputTexture atIndex:0];
    [renderEncoder setFragmentTexture:sameDimTargetTexture atIndex:1];
    
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
                        level:(int)level
                   isExclusive:(BOOL)isExclusive
{
  const BOOL debug = FALSE;
  
  if (debug) {
    NSLog(@"renderPrefixSumSweep inputTexture1: %4d x %4d and inputTexture2: %4d x %4d and outputTexture: %4d x %4d at level %d", (int)inputTexture1.width, (int)inputTexture1.height, (int)inputTexture2.width, (int)inputTexture2.height, (int)outputTexture.width, (int)outputTexture.height, level);
  }
  
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    assert(inputTexture2.width == outputTexture.width);
    assert(inputTexture2.height == outputTexture.height);
    
    // In either case, the number of pixels doubles on a up sweep
    
    int inputNumPixels = (int)inputTexture1.width * (int)inputTexture1.height;
    int outputNumPixels = (int)outputTexture.width * (int)outputTexture.height;
    
    assert((inputNumPixels * 2) == outputNumPixels);
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG
    
    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumSweep%d", level];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    if (isExclusive) {
      [renderEncoder setRenderPipelineState:self.sweepPipelineState];
    } else {
      // Inclusive scan at final render stage
      [renderEncoder setRenderPipelineState:self.inclusiveSweepPipelineState];
    }
    
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

// Process block by block order data from inputBlockOrderTexture
// using Blelloch's work efficient method. This parallel prefix sum
// generates an exclusive prefix sum and the result is written to
// outputBlockOrderTexture.

- (void) renderPrefixSum:(MetalRenderContext*)mrc
           commandBuffer:(id<MTLCommandBuffer>)commandBuffer
             renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
             isExclusive:(BOOL)isExclusive
{
  const BOOL debug = FALSE;
  
  // Determine how to recurse based on configuration in renderFrame
  
#if defined(DEBUG)
  assert(renderFrame.reduceTextures.count == renderFrame.sweepTextures.count);
#endif // DEBUG
  
  int maxStep = (int) renderFrame.reduceTextures.count;
  
  if (debug) {
    NSLog(@"num reduce/sweep steps %3d", maxStep);
  }
  
  {
    id<MTLTexture> inputTexture = renderFrame.inputBlockOrderTexture;
    
    for (int i = 0; i < maxStep; i++) {
      id<MTLTexture> outputTexture = renderFrame.reduceTextures[i];
      id<MTLTexture> sameDimTargetTexture = renderFrame.sweepTextures[i];
      
#if defined(DEBUG)
      assert(outputTexture.width == sameDimTargetTexture.width);
      assert(outputTexture.height == sameDimTargetTexture.height);
#endif // DEBUG
      
      if (debug) {
        NSLog(@"reduce step   : %d uses reduceTextures[%2d] and reduceTextures[%2d]", i+1, i-1, i);        
        NSLog(@"inputTexture  : %4d x %4d", (int)inputTexture.width, (int)inputTexture.height);
        NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
      }
      
      [self renderPrefixSumReduce:mrc
                    commandBuffer:commandBuffer
                      renderFrame:renderFrame
                     inputTexture:inputTexture
                    outputTexture:outputTexture
             sameDimTargetTexture:sameDimTargetTexture
                            level:i+1];
      
      inputTexture = outputTexture;
    }
  }

  // Once all reduce operations have been completed the down sweep can be processed
  
  {
    int i = maxStep - 1;
    
    id<MTLTexture> inputTexture1 = renderFrame.zeroTexture;
    id<MTLTexture> inputTexture2;
    
    for ( ; i >= 0; i--) {
      // inputTexture1 is zeros or output of previous sweep
      
      // inputTexture2 is the reduce output for this level
      inputTexture2 = renderFrame.reduceTextures[i];
      
      id<MTLTexture> outputTexture = renderFrame.sweepTextures[i];
      
      if (debug) {
        NSLog(@"sweep         : step %2d uses reduceTextures[%2d] sweepTextures[%2d]", i+1, i, i);
        NSLog(@"inputTexture1 : %4d x %4d", (int)inputTexture1.width, (int)inputTexture1.height);
        NSLog(@"inputTexture2 : %4d x %4d", (int)inputTexture2.width, (int)inputTexture2.height);
        NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
      }
      
      [self renderPrefixSumSweep:mrc
                   commandBuffer:commandBuffer
                     renderFrame:renderFrame
                   inputTexture1:inputTexture1
                   inputTexture2:inputTexture2
                   outputTexture:outputTexture
                           level:i+1
                     isExclusive:TRUE];

      inputTexture1 = outputTexture;
    }
    
    // A final down sweep adds values to the original input
    
    id<MTLTexture> outputTexture = renderFrame.outputBlockOrderTexture;
    inputTexture2 = renderFrame.inputBlockOrderTexture;
    
    if (debug) {
      NSLog(@"final sweep");
      NSLog(@"inputTexture1 : %4d x %4d", (int)inputTexture1.width, (int)inputTexture1.height);
      NSLog(@"inputTexture2 : %4d x %4d", (int)inputTexture2.width, (int)inputTexture2.height);
      NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
    }
    
    [self renderPrefixSumSweep:mrc
                 commandBuffer:commandBuffer
                   renderFrame:renderFrame
                 inputTexture1:inputTexture1
                 inputTexture2:inputTexture2
                 outputTexture:outputTexture
                         level:0
                   isExclusive:isExclusive];
  }
  
  return;
}

@end
