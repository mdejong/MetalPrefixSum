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

- (void) fillBGRATexture:(id<MTLTexture>)texture pixels:(uint32_t*)pixels
{
  NSUInteger bytesPerRow = texture.width * sizeof(uint32_t);
  
  MTLRegion region = {
    { 0, 0, 0 },                   // MTLOrigin
    {texture.width, texture.height, 1} // MTLSize
  };
  
  // Copy the bytes from our data object into the texture
  [texture replaceRegion:region
             mipmapLevel:0
               withBytes:pixels
             bytesPerRow:bytesPerRow];
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

// Fill values in an 8 bit texture

- (void) fill8bitTexture:(id<MTLTexture>)texture
                   bytes:(uint8_t*)bytes
{
    NSUInteger bytesPerRow = texture.width * sizeof(uint8_t);
    
    MTLRegion region = {
      { 0, 0, 0 },                   // MTLOrigin
      {texture.width, texture.height, 1} // MTLSize
    };
    
    // Copy the bytes from our data object into the texture
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:bytes
               bytesPerRow:bytesPerRow];
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

- (void) fill16bitTexture:(id<MTLTexture>)texture halfwords:(uint16_t*)halfwords
{

  NSUInteger bytesPerRow = texture.width * sizeof(uint16_t);
  
  MTLRegion region = {
    { 0, 0, 0 },                   // MTLOrigin
    {texture.width, texture.height, 1} // MTLSize
  };
  
  // Copy the bytes from our data object into the texture
  [texture replaceRegion:region
             mipmapLevel:0
               withBytes:halfwords
             bytesPerRow:bytesPerRow];
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

@end
