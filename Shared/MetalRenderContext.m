//
//  MetalRenderContext.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object Metal references that are associated with a
//  rendering context like a view but are not defined on a
//  render frame. There is 1 render contet for N render frames.

#include "MetalRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
#import "AAPLShaderTypes.h"

// Private API

@interface MetalRenderContext ()

@property (readonly) size_t numBytesAllocated;

@end

// Main class performing the rendering
@implementation MetalRenderContext

- (void) setupMetal:(nonnull id <MTLDevice>)device
{
  NSAssert(device, @"Metal device is nil");
  NSAssert(self.device == nil, @"Metal device already set");
  self.device = device;

  id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
  NSAssert(defaultLibrary, @"defaultLibrary");
  self.defaultLibrary = defaultLibrary;
  
  self.commandQueue = [self.device newCommandQueue];
  
  int tmp = 0;
  self.identityVerticesBuffer = [self makeIdentityVertexBuffer:&tmp];
  self.identityNumVertices = tmp;

  self.inFlightSemaphore = dispatch_semaphore_create(MetalRenderContextMaxBuffersInFlight);
}

// Util to allocate a BGRA 32 bits per pixel texture
// with the given dimensions.

- (id<MTLTexture>) makeBGRATexture:(CGSize)size pixels:(uint32_t*)pixels usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  //textureDescriptor.usage = MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead;
  //textureDescriptor.usage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (pixels != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint32_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:pixels
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

// Allocate texture that contains an 8 bit int value in the range (0, 255)
// represented by a half float value.

- (id<MTLTexture>) make8bitTexture:(CGSize)size bytes:(uint8_t*)bytes usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer value in the range (0,255) inclusive
  // represented by a half float
  
  textureDescriptor.pixelFormat = MTLPixelFormatR8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (bytes != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint8_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:bytes
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

// Allocate 16 bit unsigned int texture

- (id<MTLTexture>) make16bitTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer value in the range (0,255) inclusive
  
  textureDescriptor.pixelFormat = MTLPixelFormatR16Uint;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = usage;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [self.device newTextureWithDescriptor:textureDescriptor];
  
  if (halfwords != NULL) {
    NSUInteger bytesPerRow = textureDescriptor.width * sizeof(uint16_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {textureDescriptor.width, textureDescriptor.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:halfwords
               bytesPerRow:bytesPerRow];
  }
  
  return texture;
}

// Create identity vertex buffer

- (id<MTLBuffer>) makeIdentityVertexBuffer:(int*)numPtr
{
  static const AAPLVertex quadVertices[] =
  {
    // Positions, Texture Coordinates
    { {  1,  -1 }, { 1.f, 0.f } },
    { { -1,  -1 }, { 0.f, 0.f } },
    { { -1,   1 }, { 0.f, 1.f } },
    
    { {  1,  -1 }, { 1.f, 0.f } },
    { { -1,   1 }, { 0.f, 1.f } },
    { {  1,   1 }, { 1.f, 1.f } },
  };
  
  *numPtr = sizeof(quadVertices) / sizeof(AAPLVertex);
  
  // Create our vertex buffer, and intializat it with our quadVertices array
  return [self.device newBufferWithBytes:quadVertices
                                           length:sizeof(quadVertices)
                                          options:MTLResourceStorageModeShared];
}

// Create a MTLRenderPipelineDescriptor given a vertex and fragment shader

- (id<MTLRenderPipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                              pipelineLabel:(NSString*)pipelineLabel
                             numAttachments:(int)numAttachments
                         vertexFunctionName:(NSString*)vertexFunctionName
                       fragmentFunctionName:(NSString*)fragmentFunctionName
{
  // Load the vertex function from the library
  id <MTLFunction> vertexFunction = [self.defaultLibrary newFunctionWithName:vertexFunctionName];
  NSAssert(vertexFunction, @"vertexFunction \"%@\" could not be loaded", vertexFunctionName);
  
  // Load the fragment function from the library
  id <MTLFunction> fragmentFunction = [self.defaultLibrary newFunctionWithName:fragmentFunctionName];
  NSAssert(fragmentFunction, @"fragmentFunction \"%@\" could not be loaded", fragmentFunctionName);
  
  // Set up a descriptor for creating a pipeline state object
  MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label = pipelineLabel;
  pipelineStateDescriptor.vertexFunction = vertexFunction;
  pipelineStateDescriptor.fragmentFunction = fragmentFunction;
  
  for ( int i = 0; i < numAttachments; i++ ) {
    pipelineStateDescriptor.colorAttachments[i].pixelFormat = pixelFormat;
  }
  
  NSError *error = NULL;
  
  id<MTLRenderPipelineState> state = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                 error:&error];
  
  if (!state)
  {
    // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
    //  If the Metal API validation is enabled, we can find out more information about what
    //  went wrong.  (Metal API validation is enabled by default when a debug build is run
    //  from Xcode)
    NSLog(@"Failed to created pipeline state, error %@", error);
  }
  
  return state;
}

// Setup render pixpelines

- (void) setupRenderPipelines
{
  self.renderCroppedIndexesPipelineState = [self makePipeline:MTLPixelFormatR8Unorm
                                           pipelineLabel:@"Render Cropped Indexes Pipeline"
                                          numAttachments:1
                                      vertexFunctionName:@"vertexShader"
                                    fragmentFunctionName:@"cropFromTexturesFragmentShader"];
  
    NSAssert(self.renderCroppedIndexesPipelineState, @"renderCroppedIndexesPipelineState");

  self.renderCroppedLUTIndexesPipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                pipelineLabel:@"Render Cropped LUTs Pipeline"
                                               numAttachments:1
                                           vertexFunctionName:@"vertexShader"
                                         fragmentFunctionName:@"cropFromLUTTexturesFragmentShader"];
  
    NSAssert(self.renderCroppedLUTIndexesPipelineState, @"renderCroppedLUTIndexesPipelineState");
  
  self.renderToTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                   pipelineLabel:@"Render To Texture Pipeline"
                                                  numAttachments:1
                                              vertexFunctionName:@"vertexShader"
                                            fragmentFunctionName:@"samplingShader"];
  
  self.renderFromTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                 pipelineLabel:@"Render From Texture Pipeline"
                                                numAttachments:1
                                            vertexFunctionName:@"samplingPassThroughVertexShader"
                                          fragmentFunctionName:@"samplingPassThroughFragmentShader"];
  
#if defined(DEBUG)
  
  // Debug render state to emit (X,Y) for each pixel of render texture
  
  self.debugRenderXYoffsetTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                          pipelineLabel:@"Render To XY Pipeline"
                                                         numAttachments:1
                                                     vertexFunctionName:@"vertexShader"
                                                   fragmentFunctionName:@"samplingShaderDebugOutXYCoordinates"];
  
  // Debug render state to emit INDEXES for each pixel
  
  self.debugRenderIndexesTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                         pipelineLabel:@"Render To Indexes Pipeline"
                                                        numAttachments:1
                                                    vertexFunctionName:@"vertexShader"
                                                  fragmentFunctionName:@"samplingShaderDebugOutIndexes"];
  
  // Debug render state to emit LUTI for each pixel
  
  self.debugRenderLutiTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                                      pipelineLabel:@"Render To LUTI Pipeline"
                                                     numAttachments:1
                                                 vertexFunctionName:@"vertexShader"
                                               fragmentFunctionName:@"samplingShaderDebugOutLuti"];
  
#endif // DEBUG
  
  // 12 symbol render, output to 4 BGRA attached textures
  
  self.render12PipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                    pipelineLabel:@"Huffman Decode 12 Pipeline"
                                   numAttachments:4
                               vertexFunctionName:@"vertexShader"
                             fragmentFunctionName:@"huffFragmentShaderB8W12"];

  NSAssert(self.render12PipelineState, @"render12PipelineState");
  
  self.render16PipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
                                    pipelineLabel:@"Huffman Decode 16 Pipeline"
                                   numAttachments:4
                               vertexFunctionName:@"vertexShader"
                             fragmentFunctionName:@"huffFragmentShaderB8W16"];
  
  NSAssert(self.render16PipelineState, @"render16PipelineState");
}

// Huffman render textures initialization

- (void) setupHuffRenderTextures:(CGSize)renderSize
                     renderFrame:(MetalRenderFrame*)renderFrame
{
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
  
  // Render stages
  
  renderFrame.render12Zeros = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  renderFrame.render12C0R0 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C1R0 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C2R0 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C3R0 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  renderFrame.render12C0R1 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C1R1 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C2R1 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C3R1 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  renderFrame.render12C0R2 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C1R2 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C2R2 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C3R2 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  renderFrame.render12C0R3 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C1R3 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C2R3 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render12C3R3 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  renderFrame.render16C0 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render16C1 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render16C2 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  renderFrame.render16C3 = [self makeBGRATexture:CGSizeMake(blockWidth, blockHeight) pixels:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
  
  // Render into texture that is a multiple of (blockWidth, blockHeight), this is the blit destination
  
  int combinedNumElemsWidth = 4096 / 512;
  int maxLineWidth = blockWidth * combinedNumElemsWidth;
  
  int combinedNumElemsHeight = (blockWidth * 16) / maxLineWidth;
  if (((blockWidth * 16) % maxLineWidth) != 0) {
    combinedNumElemsHeight++;
  }
  
  int combinedWidth = blockWidth * combinedNumElemsWidth;
  int combinedHeight = blockHeight * combinedNumElemsHeight;
  
  renderFrame.renderCombinedSlicesTexture = [self makeBGRATexture:CGSizeMake(combinedWidth, combinedHeight) pixels:NULL usage:MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead];
  
  // Dimensions passed into shaders
  
  renderFrame.renderTargetDimensionsAndBlockDimensionsUniform = [self.device newBufferWithLength:sizeof(RenderTargetDimensionsAndBlockDimensionsUniform) options:MTLResourceStorageModeShared];
  
  {
    RenderTargetDimensionsAndBlockDimensionsUniform *ptr = renderFrame.renderTargetDimensionsAndBlockDimensionsUniform.contents;
    ptr->width = width;
    ptr->height = height;
    ptr->blockWidth = blockWidth;
    ptr->blockHeight = blockHeight;
  }
  
  // For each block, there is one 32 bit number that stores the next bit
  // offset into the huffman code buffer. Each successful code write operation
  // will read from 1 to 16 bits and increment the counter for a specific block.
  
//  renderFrame.blockStartBitOffsets = [_device newBufferWithLength:sizeof(uint32_t)*(blockWidth*blockHeight)
//                                                          options:MTLResourceStorageModeShared];
  
  // Zero out pixels / set to known init state
  
  if ((1))
  {
    int numBytes = (int) (renderFrame.render12Zeros.width * renderFrame.render12Zeros.height * sizeof(uint32_t));
    uint32_t *pixels = malloc(numBytes);
    
#if defined(IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING)
    int numBytesBlockData = (int) _blockInitData.length;
    int numPixelsInInitBlock = (int) (_render12Zeros.width * _render12Zeros.height);
    assert(numBytesBlockData == numPixelsInInitBlock);
    
    // Each output pixel is written as BGRA where R stores the previous pixel value
    // and the BG 16 bit value is zero.
    
    uint8_t *blockValPtr = (uint8_t *) _blockInitData.bytes;
    
    for ( int i = 0; i < numPixelsInInitBlock; i++ ) {
      uint8_t blockInitVal = blockValPtr[i];
      uint32_t pixel = (blockInitVal << 16) | (0);
      pixels[i] = pixel;
    }
#else
    // Init all lanes to zero
    memset(pixels, 0, numBytes);
#endif // IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING
    
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
  
  return;
}

#if defined(DEBUG)

// Implements debug render operation where (X,Y) values are written to a buffer

- (void) debugRenderXYToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalRenderFrame*)renderFrame
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

// Debug render INDEX values out as grayscale written into the pixel

- (void) debugRenderIndexesToTexture:(id<MTLCommandBuffer>)commandBuffer
                         renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *debugRenderIndexesToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(debugRenderIndexesToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.debugRenderIndexesTexture;
    
    debugRenderIndexesToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    debugRenderIndexesToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    debugRenderIndexesToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:debugRenderIndexesToTexturePassDescriptor];
    renderEncoder.label = @"debugRenderToIndexesCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"debugRenderToIndexes"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.debugRenderIndexesTexturePipelineState];
    
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

// Debug render XY values out as 2 12 bit values

- (void) debugRenderLutiToTexture:(id<MTLCommandBuffer>)commandBuffer
                      renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *debugRenderLutiToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(debugRenderLutiToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.debugRenderLutiTexture;
    
    debugRenderLutiToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    debugRenderLutiToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    debugRenderLutiToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:debugRenderLutiToTexturePassDescriptor];
    renderEncoder.label = @"debugRenderToLutiCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"debugRenderToLuti"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.debugRenderLutiTexturePipelineState];
    
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
    
    [renderEncoder popDebugGroup]; // debugRenderToLuti
    
    [renderEncoder endEncoding];
  }
}

#endif // DEBUG

// Render pass 0 with huffman decoder

- (void) renderHuff0:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame
{
  // Render 0, write 12 symbols into 3 textures along with a bits consumed halfword
  
  MTLRenderPassDescriptor *huffRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (huffRenderPassDescriptor != nil)
  {
    huffRenderPassDescriptor.colorAttachments[0].texture = renderFrame.render12C0R0;
    huffRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[1].texture = renderFrame.render12C1R0;
    huffRenderPassDescriptor.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[1].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[2].texture = renderFrame.render12C2R0;
    huffRenderPassDescriptor.colorAttachments[2].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[2].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[3].texture = renderFrame.render12C3R0;
    huffRenderPassDescriptor.colorAttachments[3].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[3].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:huffRenderPassDescriptor];
    renderEncoder.label = @"Huff12R0";
    
    [renderEncoder pushDebugGroup: @"Huff12R0"];
    
    // Set the region of the drawable to which we'll draw.
    
    int blockWidth = (int) renderFrame.render12C0R0.width;
    int blockHeight = (int) renderFrame.render12C0R0.height;
    
    MTLViewport mtlvp = {0.0, 0.0, blockWidth, blockHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.render12PipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.render12Zeros
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.blockStartBitOffsets
                              offset:0
                             atIndex:0];
    
    // Read only buffer for huffman symbols and huffman lookup table
    
    [renderEncoder setFragmentBuffer:renderFrame.huffBuff
                              offset:0
                             atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable1
                              offset:0
                             atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable2
                              offset:0
                             atIndex:3];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:4];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render pass 1 with huffman decoder

- (void) renderHuff1:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame
{
  // Render 1, write 12 symbols into 3 textures along with a bits consumed halfword
  
  MTLRenderPassDescriptor *huffRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (huffRenderPassDescriptor != nil)
  {
    huffRenderPassDescriptor.colorAttachments[0].texture = renderFrame.render12C0R1;
    huffRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[1].texture = renderFrame.render12C1R1;
    huffRenderPassDescriptor.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[1].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[2].texture = renderFrame.render12C2R1;
    huffRenderPassDescriptor.colorAttachments[2].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[2].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[3].texture = renderFrame.render12C3R1;
    huffRenderPassDescriptor.colorAttachments[3].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[3].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:huffRenderPassDescriptor];
    renderEncoder.label = @"Huff12R1";
    
    [renderEncoder pushDebugGroup: @"Huff12R1"];
    
    // Set the region of the drawable to which we'll draw.
    
    int blockWidth = (int) renderFrame.render12C0R1.width;
    int blockHeight = (int) renderFrame.render12C0R1.height;
    
    MTLViewport mtlvp = {0.0, 0.0, blockWidth, blockHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.render12PipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.render12C3R0
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.blockStartBitOffsets
                              offset:0
                             atIndex:0];
    
    // Read only buffer for huffman symbols and huffman lookup table
    
    [renderEncoder setFragmentBuffer:renderFrame.huffBuff
                              offset:0
                             atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable1
                              offset:0
                             atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable2
                              offset:0
                             atIndex:3];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:4];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render pass 2 with huffman decoder

- (void) renderHuff2:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *huffRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (huffRenderPassDescriptor != nil)
  {
    huffRenderPassDescriptor.colorAttachments[0].texture = renderFrame.render12C0R2;
    huffRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[1].texture = renderFrame.render12C1R2;
    huffRenderPassDescriptor.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[1].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[2].texture = renderFrame.render12C2R2;
    huffRenderPassDescriptor.colorAttachments[2].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[2].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[3].texture = renderFrame.render12C3R2;
    huffRenderPassDescriptor.colorAttachments[3].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[3].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:huffRenderPassDescriptor];
    renderEncoder.label = @"Huff12R2";
    
    [renderEncoder pushDebugGroup: @"Huff12R2"];
    
    // Set the region of the drawable to which we'll draw.
    
    int blockWidth = (int) renderFrame.render12C0R2.width;
    int blockHeight = (int) renderFrame.render12C0R2.height;
    
    MTLViewport mtlvp = {0.0, 0.0, blockWidth, blockHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.render12PipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.render12C3R1
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.blockStartBitOffsets
                              offset:0
                             atIndex:0];
    
    // Read only buffer for huffman symbols and huffman lookup table
    
    [renderEncoder setFragmentBuffer:renderFrame.huffBuff
                              offset:0
                             atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable1
                              offset:0
                             atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable2
                              offset:0
                             atIndex:3];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:4];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render pass 3 with huffman decoder

- (void) renderHuff3:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *huffRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (huffRenderPassDescriptor != nil)
  {
    huffRenderPassDescriptor.colorAttachments[0].texture = renderFrame.render12C0R3;
    huffRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[1].texture = renderFrame.render12C1R3;
    huffRenderPassDescriptor.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[1].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[2].texture = renderFrame.render12C2R3;
    huffRenderPassDescriptor.colorAttachments[2].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[2].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[3].texture = renderFrame.render12C3R3;
    huffRenderPassDescriptor.colorAttachments[3].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[3].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:huffRenderPassDescriptor];
    renderEncoder.label = @"Huff12R3";
    
    [renderEncoder pushDebugGroup: @"Huff12R3"];
    
    // Set the region of the drawable to which we'll draw.
    
    int blockWidth = (int) renderFrame.render12C0R3.width;
    int blockHeight = (int) renderFrame.render12C0R3.height;
    
    MTLViewport mtlvp = {0.0, 0.0, blockWidth, blockHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.render12PipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.render12C3R2
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.blockStartBitOffsets
                              offset:0
                             atIndex:0];
    
    // Read only buffer for huffman symbols and huffman lookup table
    
    [renderEncoder setFragmentBuffer:renderFrame.huffBuff
                              offset:0
                             atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable1
                              offset:0
                             atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable2
                              offset:0
                             atIndex:3];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:4];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render pass 4 with huffman decoder, this render writes 4 BGRA values and
// does not write intermediate output values.

- (void) renderHuff4:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *huffRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (huffRenderPassDescriptor != nil)
  {
    huffRenderPassDescriptor.colorAttachments[0].texture = renderFrame.render16C0;
    huffRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[1].texture = renderFrame.render16C1;
    huffRenderPassDescriptor.colorAttachments[1].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[1].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[2].texture = renderFrame.render16C2;
    huffRenderPassDescriptor.colorAttachments[2].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[2].storeAction = MTLStoreActionStore;
    
    huffRenderPassDescriptor.colorAttachments[3].texture = renderFrame.render16C3;
    huffRenderPassDescriptor.colorAttachments[3].loadAction = MTLLoadActionDontCare;
    huffRenderPassDescriptor.colorAttachments[3].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:huffRenderPassDescriptor];
    renderEncoder.label = @"Huff16R4";
    
    [renderEncoder pushDebugGroup: @"Huff16R4"];
    
    // Set the region of the drawable to which we'll draw.
    
    int blockWidth = (int) renderFrame.render16C0.width;
    int blockHeight = (int) renderFrame.render16C0.height;
    
    MTLViewport mtlvp = {0.0, 0.0, blockWidth, blockHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.render16PipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.render12C3R3
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.blockStartBitOffsets
                              offset:0
                             atIndex:0];
    
    // Read only buffer for huffman symbols and huffman lookup table
    
    [renderEncoder setFragmentBuffer:renderFrame.huffBuff
                              offset:0
                             atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable1
                              offset:0
                             atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.huffSymbolTable2
                              offset:0
                             atIndex:3];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:4];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Blit from N huffman textures so that each texture output
// is blitted into the same output texture.

- (void) blitRenderedTextures:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalRenderFrame*)renderFrame
{
  // blit the results from the previous shaders into a "slices" texture that is
  // as tall as each block buffer.
  
  {
    NSArray *inRenderedSymbolsTextures = @[
                                           renderFrame.render12C0R0,
                                           renderFrame.render12C1R0,
                                           renderFrame.render12C2R0,
                                           renderFrame.render12C0R1,
                                           renderFrame.render12C1R1,
                                           renderFrame.render12C2R1,
                                           renderFrame.render12C0R2,
                                           renderFrame.render12C1R2,
                                           renderFrame.render12C2R2,
                                           renderFrame.render12C0R3,
                                           renderFrame.render12C1R3,
                                           renderFrame.render12C2R3,
                                           renderFrame.render16C0,
                                           renderFrame.render16C1,
                                           renderFrame.render16C2,
                                           renderFrame.render16C3,
                                           ];
    
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    
    int blockWidth = (int) renderFrame.render12C0R0.width;
    int blockHeight = (int) renderFrame.render12C0R0.height;
    
    MTLSize inTxtSize = MTLSizeMake(blockWidth, blockHeight, 1);
    MTLOrigin inTxtOrigin = MTLOriginMake(0, 0, 0);
    
    const int maxCol = 4096 / 512; // max 8 blocks in one row
    
    int outCol = 0;
    int outRow = 0;
    
    int slice = 0;
    for ( id<MTLTexture> blockTxt in inRenderedSymbolsTextures ) {
      // Blit a block of pixels to (X,Y) location that is a multiple of (blockWidth,blockHeight)
      MTLOrigin outTxtOrigin = MTLOriginMake(outCol * blockWidth, outRow * blockHeight, 0);
      
      [blitEncoder copyFromTexture:blockTxt
                       sourceSlice:0
                       sourceLevel:0
                      sourceOrigin:inTxtOrigin
                        sourceSize:inTxtSize
                         toTexture:renderFrame.renderCombinedSlicesTexture
                  destinationSlice:0
                  destinationLevel:0
                 destinationOrigin:outTxtOrigin];
      
      //NSLog(@"blit for slice %2d : write to (%5d, %5d) %4d x %4d in _renderCombinedSlices", slice, (int)outTxtOrigin.x, (int)outTxtOrigin.y, (int)inTxtSize.width, (int)inTxtSize.height);
      
      slice += 1;
      outCol += 1;
      
      if (outCol == maxCol) {
        outCol = 0;
        outRow += 1;
      }
    }
#if defined(DEBUG)
    assert(slice == 16);
#endif // DEBUG
    
    [blitEncoder endEncoding];
  }
}

// Render cropped INDEXES as bytes to 8 bit texture

- (void) renderCroppedIndexesToTexture:(id<MTLCommandBuffer>)commandBuffer
                           renderFrame:(MetalRenderFrame*)renderFrame
{
  MTLRenderPassDescriptor *renderToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(renderToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.indexesTexture;
    
    renderToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    renderToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderToTexturePassDescriptor];
    renderEncoder.label = @"RenderCroppedToTextureCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderCroppedToTexture"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.renderCroppedIndexesPipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.renderCombinedSlicesTexture
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render BGRA pixels to output texture.

- (void) renderCroppedBGRAToTexture:(id<MTLCommandBuffer>)commandBuffer
                        renderFrame:(MetalRenderFrame*)renderFrame;
{
  MTLRenderPassDescriptor *renderToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(renderToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.renderTexture;
    
    renderToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    renderToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderToTexturePassDescriptor];
    renderEncoder.label = @"RenderLUTCroppedToTextureCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderLUTCroppedToTexture"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.renderCroppedLUTIndexesPipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.renderCombinedSlicesTexture
                              atIndex:0];
    
    [renderEncoder setFragmentTexture:renderFrame.lutiOffsetsTexture
                              atIndex:1];
    [renderEncoder setFragmentTexture:renderFrame.lutsTexture
                              atIndex:2];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render into the resizeable BGRA texture

- (void) renderToTexture:(id<MTLCommandBuffer>)commandBuffer
                      renderFrame:(MetalRenderFrame*)renderFrame
{
  // Render to texture
  
  MTLRenderPassDescriptor *renderToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(renderToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.renderTexture;
    
    renderToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    renderToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderToTexturePassDescriptor];
    renderEncoder.label = @"RenderToTextureCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderToTexture"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.renderToTexturePipelineState];
    
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
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Render from the resizable BGRA output texture into the active view

- (void) renderFromTexture:(id<MTLCommandBuffer>)commandBuffer
      renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
               renderFrame:(MetalRenderFrame*)renderFrame
             viewportWidth:(int)viewportWidth
            viewportHeight:(int)viewportHeight
{
  if(renderPassDescriptor != nil)
  {
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"RenderBGRACommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderFromTexture"];
    
    // Set the region of the drawable to which we'll draw.
    MTLViewport mtlvp = {0.0, 0.0, viewportWidth, viewportHeight, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.renderFromTexturePipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.renderTexture
                              atIndex:AAPLTextureIndexBaseColor];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderFromTexture
    
    [renderEncoder endEncoding];
  }
}

@end
