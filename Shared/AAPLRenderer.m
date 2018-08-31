

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which perfoms Metal setup and per frame rendering
*/
@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
#import "AAPLShaderTypes.h"

#import <CoreVideo/CoreVideo.h>

#import "DeltaEncoder.h"

#import "ImageInputFrame.h"

#import "Util.h"

#import "MetalRenderContext.h"
#import "MetalPrefixSumRenderContext.h"
#import "MetalPrefixSumRenderFrame.h"

const static unsigned int blockDim = 8;

@interface AAPLRenderer ()

@property (nonatomic, retain) MTKView *mtkView;

// A single render context contains refs to Metal specific

@property (nonatomic, retain) MetalRenderContext *mrc;

@property (nonatomic, retain) MetalPrefixSumRenderContext *mpsrc;

@property (nonatomic, retain) ImageInputFrame *imageInputFrame;

@property (nonatomic, retain) MetalPrefixSumRenderFrame *mpsRenderFrame;

@end

// Main class performing the rendering
@implementation AAPLRenderer
{
  // The device (aka GPU) we're using to render
  //id <MTLDevice> _device;
  
  // 12 and 16 symbol render pipelines
  //id<MTLRenderPipelineState> _render12PipelineState;
  //id<MTLRenderPipelineState> _render16PipelineState;
  
  // The Metal textures that will hold fragment shader output
  
    // render to texture pipeline is used to render into a texture
    id<MTLRenderPipelineState> _renderToTexturePipelineState;
  
    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id<MTLRenderPipelineState> _renderFromTexturePipelineState;

    // The command Queue from which we'll obtain command buffers
    //id<MTLCommandQueue> _commandQueue;

    // Texture cache
    CVMetalTextureCacheRef _textureCache;
  
    id<MTLTexture> _render_texture;
  
    // The Metal buffer in which we store our vertex data
    //id<MTLBuffer> _vertices;

    // The Metal buffer that will hold render dimensions
    id<MTLBuffer> _renderTargetDimensionsAndBlockDimensionsUniform;
  
  // The Metal buffer stores the number of bits into the
  // variable length codes buffer where the symbol at a given
  // block begins. This table keeps the codes
  // tightly packed into bytes.

  id<MTLBuffer> _blockStartBitOffsets;
  
  // The Metal buffer where encoded bits are stored
  id<MTLBuffer> _bitsBuff;
  
    // The number of vertices in our vertex buffer
    //NSUInteger _numVertices;

    // The current size of our view so we can use this in our render pipeline
    vector_uint2 _viewportSize;
  
    int isCaptureRenderedTextureEnabled;
  
  NSData *_huffData;

  NSData *_imageInputBytes;

  NSData *_blockByBlockReorder;

  NSData *_blockInitData;

  NSData *_outBlockOrderSymbolsData;

  NSData *_blockOrderSymbolsPreDeltas;
  
  int renderWidth;
  int renderHeight;
  
  int renderBlockWidth;
  int renderBlockHeight;
}

// Util function that generates a texture object at a given dimension.
// This texture contains 32 bit pixel values with BGRA unsigned byte components.

- (id<MTLTexture>) makeBGRATexture:(CGSize)size pixels:(uint32_t*)pixels
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

  textureDescriptor.textureType = MTLTextureType2D;
  
  textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [self.mrc.device newTextureWithDescriptor:textureDescriptor];
  
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

// Allocate a 32 bit CoreVideo backing buffer and texture

- (id<MTLTexture>) makeBGRACoreVideoTexture:(CGSize)size
                        cvPixelBufferRefPtr:(CVPixelBufferRef*)cvPixelBufferRefPtr
{
  int width = (int) size.width;
  int height = (int) size.height;
  
  // CoreVideo pixel buffer backing the indexes texture
  
  NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], kCVPixelBufferMetalCompatibilityKey,
                           [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                           [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                           nil];
  
  CVPixelBufferRef pxbuffer = NULL;
  
  CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                        width,
                                        height,
                                        kCVPixelFormatType_32BGRA,
                                        (__bridge CFDictionaryRef) options,
                                        &pxbuffer);
  
  NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
  
  *cvPixelBufferRefPtr = pxbuffer;
  
  CVMetalTextureRef cvTexture = NULL;
  
  CVReturn ret = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _textureCache,
                                                           pxbuffer,
                                                           nil,
                                                           MTLPixelFormatBGRA8Unorm,
                                                           CVPixelBufferGetWidth(pxbuffer),
                                                           CVPixelBufferGetHeight(pxbuffer),
                                                           0,
                                                           &cvTexture);
  
  NSParameterAssert(ret == kCVReturnSuccess && cvTexture != NULL);
  
  id<MTLTexture> metalTexture = CVMetalTextureGetTexture(cvTexture);
  
  CFRelease(cvTexture);
  
  return metalTexture;
}

// Allocate 8 bit unsigned int texture

- (id<MTLTexture>) make8bitTexture:(CGSize)size bytes:(uint8_t*)bytes
{
  MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
  
  textureDescriptor.textureType = MTLTextureType2D;
  
  // Each value in this texture is an 8 bit integer value in the range (0,255) inclusive
  // represented by a half float
  
  textureDescriptor.pixelFormat = MTLPixelFormatR8Unorm;
  textureDescriptor.width = (int) size.width;
  textureDescriptor.height = (int) size.height;
  
  textureDescriptor.usage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
  
  // Create our texture object from the device and our descriptor
  id<MTLTexture> texture = [self.mrc.device newTextureWithDescriptor:textureDescriptor];
  
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

+ (NSString*) getResourcePath:(NSString*)resFilename
{
  NSBundle* appBundle = [NSBundle mainBundle];
  NSString* movieFilePath = [appBundle pathForResource:resFilename ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
  return movieFilePath;
}

- (void) copyInto32bitCoreVideoTexture:(CVPixelBufferRef)cvPixelBufferRef
                                pixels:(uint32_t*)pixels
{
  size_t width = CVPixelBufferGetWidth(cvPixelBufferRef);
  size_t height = CVPixelBufferGetHeight(cvPixelBufferRef);
  
  CVPixelBufferLockBaseAddress(cvPixelBufferRef, 0);
  
  void *baseAddress = CVPixelBufferGetBaseAddress(cvPixelBufferRef);
  
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBufferRef);
  assert(bytesPerRow >= (width * sizeof(uint32_t)));
  
  for ( int row = 0; row < height; row++ ) {
    uint32_t *ptr = baseAddress + (row * bytesPerRow);
    memcpy(ptr, (void*) (pixels + (row * width)), width * sizeof(uint32_t));
  }

  if ((0)) {
    for ( int row = 0; row < height; row++ ) {
      uint32_t *rowPtr = baseAddress + (row * bytesPerRow);
      for ( int col = 0; col < width; col++ ) {
        fprintf(stdout, "0x%08X ", rowPtr[col]);
      }
      fprintf(stdout, "\n");
    }
  }
  
  CVPixelBufferUnlockBaseAddress(cvPixelBufferRef, 0);
  
  return;
}

// Query a texture that contains byte values and return in
// a buffer of uint8_t typed values.

+ (NSData*) getTextureBytes:(id<MTLTexture>)texture
{
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint8_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
           bytesPerRow:width*sizeof(uint8_t)
         bytesPerImage:width*height*sizeof(uint8_t)
            fromRegion:MTLRegionMake2D(0, 0, width, height)
           mipmapLevel:0
                 slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}

// Query pixel contents of a texture and return as uint32_t
// values in a NSData*.

+ (NSData*) getTexturePixels:(id<MTLTexture>)texture
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint32_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
        bytesPerRow:width*sizeof(uint32_t)
      bytesPerImage:width*height*sizeof(uint32_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}


+ (void) calculateThreadgroup:(CGSize)inSize
                     blockDim:(int)blockDim
                      sizePtr:(MTLSize*)sizePtr
                     countPtr:(MTLSize*)countPtr
{
  MTLSize mSize;
  MTLSize mCount;
  
  mSize = MTLSizeMake(blockDim, blockDim, 1);

  // Calculate the number of rows and columns of thread groups given the width of our input image.
  //   Ensure we cover the entire image (or more) so we process every pixel.
  
  //int width = (inSize.width  + mSize.width -  1) / mSize.width;
  //int height = (inSize.height + mSize.height - 1) / mSize.height;
  
  int width = inSize.width;
  int height = inSize.height;
  
  mCount = MTLSizeMake(width, height, 1);
  mCount.depth = 1; // 2D only
  
  *sizePtr = mSize;
  *countPtr = mCount;
  
  return;
}

- (void) setupBlockEncoding
{
  unsigned int width = self->renderWidth;
  unsigned int height = self->renderHeight;
  
  unsigned int blockWidth = self->renderBlockWidth;
  unsigned int blockHeight = self->renderBlockHeight;
  
  NSMutableData *outCodes = [NSMutableData data];
  NSMutableData *outBlockBitOffsets = [NSMutableData data];
    
  if ((0)) {
        printf("image order for %5d x %5d image\n", width, height);
      
      uint8_t* inBytes = (uint8_t*)_imageInputBytes.bytes;
      
        for ( int row = 0; row < height; row++ ) {
          for ( int col = 0; col < width; col++ ) {
              uint8_t byteVal = inBytes[(row * width) + col];
              printf("0x%02X ", byteVal);
          }
            
          printf("\n");
        }
        
        printf("image order done\n");
    }
  
  // To encode symbols with huffman block encoding, the order of the symbols
  // needs to be broken up so that the input ordering is in terms of blocks and
  // the partial blocks are handled in a way that makes it possible to process
  // the data with the shader. Note that this logic will split into fixed block
  // size with zero padding, so the output would need to be reordered back to
  // image order and then trimmed to width and height in order to match.
  
  int outBlockOrderSymbolsNumBytes = (blockDim * blockDim) * (blockWidth * blockHeight);
  
  // Generate input that is zero padded out to the number of blocks needed
  NSMutableData *outBlockOrderSymbolsData = [NSMutableData dataWithLength:outBlockOrderSymbolsNumBytes];
  uint8_t *outBlockOrderSymbolsPtr = (uint8_t *) outBlockOrderSymbolsData.bytes;
  
  [Util splitIntoBlocksOfSize:blockDim
                      inBytes:(uint8_t*)_imageInputBytes.bytes
                     outBytes:outBlockOrderSymbolsPtr
                        width:width
                       height:height
             numBlocksInWidth:blockWidth
            numBlocksInHeight:blockHeight
                    zeroValue:0];
    
  // Make a copy of the block order symbols, since calculating deltas will replace
  // these symbols in place to minimize memory.

  _blockOrderSymbolsPreDeltas = [NSMutableData dataWithData:outBlockOrderSymbolsData];
  
#if defined(DEBUG)
    NSData *blockOrderSymbolsCopy = [NSMutableData dataWithData:outBlockOrderSymbolsData];
#endif // DEBUG
  
  if ((0)) {
    //        for (int i = 0; i < outBlockOrderSymbolsNumBytes; i++) {
    //          printf("outBlockOrderSymbolsPtr[%5i] = %d\n", i, outBlockOrderSymbolsPtr[i]);
    //        }
    
    printf("block order for %5d blocks\n", (blockWidth * blockHeight));
    
    for ( int blocki = 0; blocki < (blockWidth * blockHeight); blocki++ ) {
      printf("block %5d : ", blocki);
      
      uint8_t *blockStartPtr = outBlockOrderSymbolsPtr + (blocki * (blockDim * blockDim));
      
      for (int i = 0; i < (blockDim * blockDim); i++) {
        printf("%5d ", blockStartPtr[i]);
      }
      printf("\n");
    }
    
    printf("block order done\n");
  }
  
  if ((1)) @autoreleasepool {
    // byte deltas
    
    NSMutableArray *mBlocks = [NSMutableArray array];
    
    for ( int blocki = 0; blocki < (blockWidth * blockHeight); blocki++ ) {
      NSMutableData *mRowData = [NSMutableData data];
      uint8_t *blockStartPtr = outBlockOrderSymbolsPtr + (blocki * (blockDim * blockDim));
      [mRowData appendBytes:blockStartPtr length:(blockDim * blockDim)];
      [mBlocks addObject:mRowData];
    }
    
    // Convert blocks to deltas
    
    NSMutableArray *mRowsOfDeltas = [NSMutableArray array];
    
#if defined(IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING)
    NSMutableData *mBlockInitData = [NSMutableData dataWithCapacity:(blockWidth * blockHeight)];
#endif
    
    for ( NSMutableData *blockData in mBlocks ) {
      NSData *deltasData = [DeltaEncoder encodeSignedByteDeltas:blockData];
      
#if defined(IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING)
      // When saving the first element of a block, do the deltas
      // first and then pull out the first delta and set the delta
      // byte to zero. This increases the count of the zero delta
      // value and reduces the size of the generated tree while
      // storing the block init value wo a huffman code.
      {
        NSMutableData *mDeltasData = [NSMutableData dataWithData:deltasData];
        
        uint8_t *bytePtr = mDeltasData.mutableBytes;
        uint8_t firstByte = bytePtr[0];
        bytePtr[0] = 0;
        
        [mBlockInitData appendBytes:&firstByte length:1];
        
        deltasData = [NSData dataWithData:mDeltasData];
      }
#endif // IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING
      
      [mRowsOfDeltas addObject:deltasData];
      
#if defined(DEBUG)
      // Check that decoding generates the original input
      
# if defined(IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING)
      // Undo setting of the first element to zero.
      {
        uint8_t *initBytePtr = mBlockInitData.mutableBytes;
        uint8_t firstByte = initBytePtr[mBlockInitData.length-1];
        
        NSMutableData *mDeltasData = [NSMutableData dataWithData:deltasData];
        uint8_t *deltasBytePtr = mDeltasData.mutableBytes;
        
        deltasBytePtr[0] = firstByte;
        
        deltasData = [NSData dataWithData:mDeltasData];
      }
# endif // IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING
      
      NSData *decodedDeltas = [DeltaEncoder decodeSignedByteDeltas:deltasData];
      NSAssert([decodedDeltas isEqualToData:blockData], @"decoded deltas");
#endif // DEBUG
    }
    
    // Write delta values back over outBlockOrderSymbolsPtr memory
    
    int outWritei = 0;
    
    for ( NSData *deltaRow in mRowsOfDeltas ) {
      uint8_t *ptr = (uint8_t *) deltaRow.bytes;
      const int len = (int) deltaRow.length;
      for ( int i = 0; i < len; i++) {
        outBlockOrderSymbolsPtr[outWritei++] = ptr[i];
      }
    }
    
#if defined(IMPL_DELTAS_AND_INIT_ZERO_DELTA_BEFORE_HUFF_ENCODING)
    _blockInitData = [NSData dataWithData:mBlockInitData];
#endif
  }
  
  if ((0)) {
    //        for (int i = 0; i < outBlockOrderSymbolsNumBytes; i++) {
    //          printf("outBlockOrderSymbolsPtr[%5i] = %d\n", i, outBlockOrderSymbolsPtr[i]);
    //        }
    
    printf("deltas block order\n");
    
    for ( int blocki = 0; blocki < (blockWidth * blockHeight); blocki++ ) {
      printf("block %5d : ", blocki);
      
      uint8_t *blockStartPtr = outBlockOrderSymbolsPtr + (blocki * (blockDim * blockDim));
      
      for (int i = 0; i < (blockDim * blockDim); i++) {
        printf("%5d ", blockStartPtr[i]);
      }
      printf("\n");
    }
    
    printf("deltas block order done\n");
  }
    
    if ((0)) {
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *path = [tmpDir stringByAppendingPathComponent:@"block_deltas.bytes"];
        [outBlockOrderSymbolsData writeToFile:path atomically:TRUE];
        NSLog(@"wrote %@", path);
    }
    
    if ((0)) {
        NSString *tmpDir = NSTemporaryDirectory();
        
        // convert signed bytes to unsigned numbers
        
        NSMutableData *mData = [NSMutableData data];
        
        uint8_t *bytePtr = (uint8_t *) outBlockOrderSymbolsData.bytes;
        int bytePtrLength = (int) outBlockOrderSymbolsData.length;
        
        for (int i = 0; i < bytePtrLength; i++) {
            uint8_t byteVal = bytePtr[i];
            // already converted to zerod deltas
            //uint8_t unsignedByteVal = pixelpack_int8_to_offset_uint8(byteVal);
            //[mData appendBytes:&unsignedByteVal length:1];
            [mData appendBytes:&byteVal length:1];
        }
        
        NSString *path2 = [tmpDir stringByAppendingPathComponent:@"block_deltas_unsigned.bytes"];
        [mData writeToFile:path2 atomically:TRUE];
        NSLog(@"wrote %@", path2);
    }

  // number of blocks must be an exact multiple of the block dimension
  
  assert((outBlockOrderSymbolsNumBytes % (blockDim * blockDim)) == 0);
  
  // Copy encoded block order bytes

  _outBlockOrderSymbolsData = [NSData dataWithData:outBlockOrderSymbolsData];
  
  return;
}

// Initialize with the MetalKit view from which we'll obtain our metal device

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
      isCaptureRenderedTextureEnabled = 1;
      
      mtkView.depthStencilPixelFormat = MTLPixelFormatInvalid;
      
      mtkView.preferredFramesPerSecond = 30;
      
      //_device = mtkView.device;

      if (isCaptureRenderedTextureEnabled) {
        mtkView.framebufferOnly = false;
      }
      
      self.mrc = [[MetalRenderContext alloc] init];
      
      self.mpsrc = [[MetalPrefixSumRenderContext alloc] init];
      
      self.mtkView = mtkView;
      [self.mrc setupMetal:mtkView.device];
      
      [self.mpsrc setupRenderPipelines:self.mrc];

      // Texture Cache
      
//      {
//        // Disable flushing of textures
//
//        NSDictionary *cacheAttributes = @{
//                                          (NSString*)kCVMetalTextureCacheMaximumTextureAgeKey: @(0),
//                                          };
//
////        NSDictionary *cacheAttributes = nil;
//
//        CVReturn status = CVMetalTextureCacheCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)cacheAttributes, _device, nil, &_textureCache);
//        NSParameterAssert(status == kCVReturnSuccess && _textureCache != NULL);
//      }
      
      // Query size and byte data for input frame that will be rendered
      
      ImageInputFrameConfig hcfg;
      
//      hcfg = TEST_4x4_INCREASING1;
//      hcfg = TEST_4x4_INCREASING2;
//      hcfg = TEST_4x8_INCREASING1;
//      hcfg = TEST_2x8_INCREASING1;
//      hcfg = TEST_6x4_NOT_SQUARE;
      hcfg = TEST_8x8_IDENT;
//      hcfg = TEST_8x8_DELTA_IDENT;
//      hcfg = TEST_16x8_IDENT;
//      hcfg = TEST_16x16_IDENT;
//      hcfg = TEST_16x16_IDENT2;
//      hcfg = TEST_16x16_IDENT3;
      
//        hcfg = TEST_8x8_IDENT_2048;
//        hcfg = TEST_8x8_IDENT_4096;

      //hcfg = TEST_LARGE_RANDOM;
      //hcfg = TEST_IMAGE1;
      //hcfg = TEST_IMAGE2;
      //hcfg = TEST_IMAGE3;
      //hcfg = TEST_IMAGE4;
      
      ImageInputFrame *renderFrame = [ImageInputFrame frameForConfig:hcfg];
      
      self.imageInputFrame = renderFrame;
      
      unsigned int width = renderFrame.renderWidth;
      unsigned int height = renderFrame.renderHeight;
      
      unsigned int blockWidth = width / blockDim;
      if ((width % blockDim) != 0) {
        blockWidth += 1;
      }
      
      unsigned int blockHeight = height / blockDim;
      if ((height % blockDim) != 0) {
        blockHeight += 1;
      }
      
      self->renderWidth = width;
      self->renderHeight = height;
      
      renderFrame.renderBlockWidth = blockWidth;
      renderFrame.renderBlockHeight = blockHeight;
      
      self->renderBlockWidth = blockWidth;
      self->renderBlockHeight = blockHeight;
      
      _renderTargetDimensionsAndBlockDimensionsUniform = [self.mrc.device newBufferWithLength:sizeof(RenderTargetDimensionsAndBlockDimensionsUniform)
                                                     options:MTLResourceStorageModeShared];
      
      {
        RenderTargetDimensionsAndBlockDimensionsUniform *ptr = _renderTargetDimensionsAndBlockDimensionsUniform.contents;
        ptr->width = width;
        ptr->height = height;
        ptr->blockWidth = blockWidth;
        ptr->blockHeight = blockHeight;
      }
      
      // Allocate prefix sum textures
      
      MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
      
      // This block size indicates the number of prefix sum values to sum
      // together. Pass (32,32) for a (32 * 32) values per block.
      
      CGSize prefixSumBlockSize = CGSizeMake(width, height);
      CGSize blockSize = CGSizeMake(blockDim, blockDim);
      
      [self.mpsrc setupRenderTextures:self.mrc renderSize:prefixSumBlockSize blockSize:blockSize renderFrame:mpsrf];
      
      self.mpsRenderFrame = mpsrf;
      
      // Crop/Copy shader that operates on image order bytes and write BGRA grayscale pixels
      
      {
        // Load the vertex function from the library
        id <MTLFunction> vertexFunction = [self.mrc.defaultLibrary newFunctionWithName:@"vertexShader"];
        
        // Load the fragment function from the library
        
        id <MTLFunction> fragmentFunction = [self.mrc.defaultLibrary newFunctionWithName:@"samplingCropShader"];
        assert(fragmentFunction);
        
        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Render To Texture Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        //pipelineStateDescriptor.stencilAttachmentPixelFormat =  mtkView.depthStencilPixelFormat; // MTLPixelFormatStencil8
        
        NSError *error = nil;
        
        _renderToTexturePipelineState = [self.mrc.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                error:&error];
        if (!_renderToTexturePipelineState)
        {
          // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
          //  If the Metal API validation is enabled, we can find out more information about what
          //  went wrong.  (Metal API validation is enabled by default when a debug build is run
          //  from Xcode)
          NSLog(@"Failed to created pipeline state, error %@", error);
        }
        
      }
      
      // Simple Render
      
      {
        // Render to texture pipeline, simple pass through shader
        
        // Load the vertex function from the library
        id <MTLFunction> vertexFunction = [self.mrc.defaultLibrary newFunctionWithName:@"vertexShader"];
        
        // Load the fragment function from the library
        id <MTLFunction> fragmentFunction = [self.mrc.defaultLibrary newFunctionWithName:@"samplingPassThroughFragmentShader"];
        
        {
          // Set up a descriptor for creating a pipeline state object
          MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
          pipelineStateDescriptor.label = @"Render From Texture Pipeline";
          pipelineStateDescriptor.vertexFunction = vertexFunction;
          pipelineStateDescriptor.fragmentFunction = fragmentFunction;
          pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
          //pipelineStateDescriptor.stencilAttachmentPixelFormat =  mtkView.depthStencilPixelFormat; // MTLPixelFormatStencil8
          
          NSError *error = nil;
          
          _renderFromTexturePipelineState = [self.mrc.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                    error:&error];
          if (!_renderFromTexturePipelineState)
          {
            // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
            //  If the Metal API validation is enabled, we can find out more information about what
            //  went wrong.  (Metal API validation is enabled by default when a debug build is run
            //  from Xcode)
            NSLog(@"Failed to created pipeline state, error %@", error);
          }
        }
      }
      
      _render_texture = [self makeBGRATexture:CGSizeMake(width,height) pixels:NULL];

      // Render stages
      
      _imageInputBytes = renderFrame.inputData;
      
      [self setupBlockEncoding];
      
    } // end of init if block
  
    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

- (NSString*) codeBitsAsString:(uint32_t)code width:(int)width
{
  NSMutableString *mStr = [NSMutableString string];
  int c4 = 1;
  for ( int i = 0; i < width; i++ ) {
    bool isOn = ((code & (0x1 << i)) != 0);
    if (isOn) {
      [mStr insertString:@"1" atIndex:0];
    } else {
      [mStr insertString:@"0" atIndex:0];
    }
    
    if ((c4 == 4) && (i != (width - 1))) {
      [mStr insertString:@"-" atIndex:0];
      c4 = 1;
    } else {
      c4++;
    }
  }
  return [NSString stringWithString:mStr];
}

// Dump texture that contains a 4 byte values in each BGRA pixel

- (void) dump4ByteTexture:(id<MTLTexture>)outTexture
                    label:(NSString*)label
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) outTexture.width;
  int height = (int) outTexture.height;
  
  NSData *pixelsData = [self.class getTexturePixels:outTexture];
  uint32_t *pixelsPtr = ((uint32_t*) pixelsData.bytes);
  
  // Dump output words as bytes
  
  if ((1)) {
    fprintf(stdout, "%s\n", [label UTF8String]);
    
    // Dump output words as BGRA
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint32_t v = pixelsPtr[offset];
        //fprintf(stdout, "%5d ", v);
        fprintf(stdout, "0x%08X ", v);
      }
      fprintf(stdout, "\n");
    }
    
    fprintf(stdout, "done\n");
  }
  
  if ((1)) {
    fprintf(stdout, "%s as bytes\n", [label UTF8String]);
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint32_t v = pixelsPtr[offset];
        
        for (int i = 0; i < 4; i++) {
          uint32_t bVal = (v >> (i * 8)) & 0xFF;
          fprintf(stdout, "%d ", bVal);
        }
      }
      fprintf(stdout, "\n");
    }
    
    fprintf(stdout, "done\n");
  }
}


// Dump texture that contains simple grayscale pixel values

- (void) dump8BitTexture:(id<MTLTexture>)outTexture
                   label:(NSString*)label
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) outTexture.width;
  int height = (int) outTexture.height;
  
  NSData *bytesData = [self.class getTextureBytes:outTexture];
  uint8_t *bytesPtr = (uint8_t*) bytesData.bytes;
  
  // Dump output words as bytes
  
  if ((1)) {
    fprintf(stdout, "%s as bytes\n", [label UTF8String]);
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t v = bytesPtr[offset];
        fprintf(stdout, "%3d ", v);
      }
      fprintf(stdout, "\n");
    }
    
    fprintf(stdout, "done\n");
  }
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
  if (_outBlockOrderSymbolsData == nil) {
    return;
  }
  
  // Create a new command buffer
  
  id <MTLCommandBuffer> commandBuffer = [self.mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"RenderBGRACommand";
  
  // --------------------------------------------------------------------------
  
  // Prefix sum setup and render steps
  
  MetalPrefixSumRenderFrame *mpsRenderFrame = self.mpsRenderFrame;
  
  [self.mpsrc renderPrefixSum:self.mrc commandBuffer:commandBuffer renderFrame:mpsRenderFrame isExclusive:FALSE];
  
  id<MTLTexture> prefixSumOutputTexture = (id<MTLTexture>) mpsRenderFrame.outputBlockOrderTexture;
  
  {
    // Copy prefix sum delta input bytes into block order texture
    id<MTLTexture> inputTexture = (id<MTLTexture>) mpsRenderFrame.inputBlockOrderTexture;
    
    NSAssert(_outBlockOrderSymbolsData, @"_outBlockOrderSymbolsData");
    
    // Convert deltas from zigzag back to plain deltas, then sum to undo deltas
    
    NSData *decodedDeltas = [DeltaEncoder decodeZigZagBytes:_outBlockOrderSymbolsData];
    [self.mrc fill8bitTexture:inputTexture bytes:(uint8_t*)decodedDeltas.bytes];
  }
  
  // Cropping copy operation from _renderToTexturePipelineState which is unsigned int values
  // to _render_texture which contains pixel values. This copy operation will expand single
  // byte values emitted by the huffman decoder as grayscale pixels.
  
  MTLRenderPassDescriptor *renderToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderToTexturePassDescriptor != nil)
  {
    renderToTexturePassDescriptor.colorAttachments[0].texture = _render_texture;
    renderToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderToTexturePassDescriptor];
    renderEncoder.label = @"RenderToTextureCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderToTexture"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, _render_texture.width, _render_texture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:_renderToTexturePipelineState];
    
    [renderEncoder setVertexBuffer:self.mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:prefixSumOutputTexture
                              atIndex:0];
    
    [renderEncoder setFragmentBuffer:_renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.mrc.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }

  // Render the already cropped image and resize to fit view drawable size
  
  MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
  
  if(renderPassDescriptor != nil)
  {
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"RenderBGRACommandEncoder";
    
    [renderEncoder pushDebugGroup: @"RenderFromTexture"];
    
    // Set the region of the drawable to which we'll draw.
    MTLViewport mtlvp = {0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:_renderFromTexturePipelineState];
    
    [renderEncoder setVertexBuffer:self.mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:_render_texture
                              atIndex:AAPLTextureIndexes];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.mrc.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderFromTexture
   
    [renderEncoder endEncoding];
    
    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:view.currentDrawable];
    
    if (isCaptureRenderedTextureEnabled) {
      // Finalize rendering here & push the command buffer to the GPU
      [commandBuffer commit];
      [commandBuffer waitUntilCompleted];
    }

    // Print output of render pass in stages
    
    const int assertOnValueDiff = 1;
    
    if (isCaptureRenderedTextureEnabled) {
      
      // Dump contents of prefix sum render output
      
      const BOOL debug = TRUE;
      
      id<MTLTexture> inputTexture = (id<MTLTexture>) mpsRenderFrame.inputBlockOrderTexture;
      
      if (debug) {
      [self dump8BitTexture:inputTexture label:@"inputTexture"];
      }
      
      id<MTLTexture> outputTexture = (id<MTLTexture>) mpsRenderFrame.outputBlockOrderTexture;

      if (debug) {
      [self dump8BitTexture:outputTexture label:@"outputTexture"];
      }
      
      // FIXME: compare to original input?
      
      uint8_t *bytePtr = (uint8_t *) _blockOrderSymbolsPreDeltas.bytes;
      
      NSData *textureData = [self.class getTextureBytes:outputTexture];
      uint8_t *texturePtr = (uint8_t*) textureData.bytes;
      
      assert(_blockOrderSymbolsPreDeltas.length == textureData.length);
      int cmp = memcmp(bytePtr, texturePtr, _blockOrderSymbolsPreDeltas.length);
      assert(cmp == 0);
    }
    
    // Capture the render to texture state at the render to size
    if (isCaptureRenderedTextureEnabled && 1) {
      // Query output texture
      
      id<MTLTexture> outTexture = _render_texture;
      
      // Copy texture data into debug framebuffer, note that this include 2x scale
      
      int width = (int) outTexture.width;
      int height = (int) outTexture.height;
      
      NSData *pixelsData = [self.class getTexturePixels:outTexture];
      uint32_t *pixelsPtr = ((uint32_t*) pixelsData.bytes);
      
      // Dump output words as BGRA
      
      if ((1)) {
        // Dump 24 bit values as int
        
        fprintf(stdout, "_render_texture\n");
        
        for ( int row = 0; row < height; row++ ) {
          for ( int col = 0; col < width; col++ ) {
            int offset = (row * width) + col;
            //uint32_t v = pixelsPtr[offset] & 0x00FFFFFF;
            //fprintf(stdout, "%5d ", v);
            //fprintf(stdout, "%6X ", v);
            uint32_t v = pixelsPtr[offset];
            fprintf(stdout, "0x%08X ", v);
          }
          fprintf(stdout, "\n");
        }
        
        fprintf(stdout, "done\n");
      }

      if ((0)) {
        // Dump 8bit B comp as int
        
        fprintf(stdout, "_render_texture\n");
        
        for ( int row = 0; row < height; row++ ) {
          for ( int col = 0; col < width; col++ ) {
            int offset = (row * width) + col;
            //uint32_t v = pixelsPtr[offset] & 0x00FFFFFF;
            //fprintf(stdout, "%5d ", v);
            //fprintf(stdout, "%6X ", v);
            uint32_t v = pixelsPtr[offset] & 0xFF;
            //fprintf(stdout, "0x%08X ", v);
            fprintf(stdout, "%3d ", v);
          }
          fprintf(stdout, "\n");
        }
        
        fprintf(stdout, "done\n");
      }
      
      if ((1)) {
        // Dump 24 bit values as int
        
        fprintf(stdout, "expected symbols\n");
        
        NSData *expectedData = _imageInputBytes;
        assert(expectedData);
        uint8_t *expectedDataPtr = (uint8_t *) expectedData.bytes;
        //const int numBytes = (int)expectedData.length * sizeof(uint8_t);
        
        for ( int row = 0; row < height; row++ ) {
          for ( int col = 0; col < width; col++ ) {
            int offset = (row * width) + col;
            //int v = expectedDataPtr[offset];
            //fprintf(stdout, "%6X ", v);
            
            uint32_t v = expectedDataPtr[offset] & 0xFF;
            fprintf(stdout, "%3d ", v);
          }
          fprintf(stdout, "\n");
        }
        
        fprintf(stdout, "done\n");
      }
      
      // Compare output to expected output
      
      if ((1)) {
        NSData *expectedData = _imageInputBytes;
        assert(expectedData);
        uint8_t *expectedDataPtr = (uint8_t *) expectedData.bytes;
        const int numBytes = (int)expectedData.length * sizeof(uint8_t);
        
        uint32_t *renderedPixelPtr = pixelsPtr;
        
        for ( int row = 0; row < height; row++ ) {
          for ( int col = 0; col < width; col++ ) {
            int offset = (row * width) + col;
            
            int expectedSymbol = expectedDataPtr[offset]; // read byte
            int renderedSymbol = renderedPixelPtr[offset] & 0xFF; // compare to just the B component
            
            if (renderedSymbol != expectedSymbol) {
              printf("renderedSymbol != expectedSymbol : %3d != %3d at (X,Y) (%3d,%3d) offset %d\n", renderedSymbol, expectedSymbol, col, row, offset);
              
              if (assertOnValueDiff) {
                assert(0);
              }

            }
          }
        }
        
        assert(numBytes == (width * height));
      }
      
      // end of capture logic
    }
    
    // Get pixel out of outTexture ?
    
    if (isCaptureRenderedTextureEnabled) {
      // Query output texture after resize
      
      id<MTLTexture> outTexture = renderPassDescriptor.colorAttachments[0].texture;
      
      // Copy texture data into debug framebuffer, note that this include 2x scale
      
      int width = _viewportSize.x;
      int height = _viewportSize.y;
      
      NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint32_t)];
      
      [outTexture getBytes:(void*)mFramebuffer.mutableBytes
               bytesPerRow:width*sizeof(uint32_t)
             bytesPerImage:width*height*sizeof(uint32_t)
                fromRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                     slice:0];
      
      // Dump output words as BGRA
      
      if ((0)) {
        for ( int row = 0; row < height; row++ ) {
          uint32_t *rowPtr = ((uint32_t*) mFramebuffer.mutableBytes) + (row * width);
          for ( int col = 0; col < width; col++ ) {
            fprintf(stdout, "0x%08X ", rowPtr[col]);
          }
          fprintf(stdout, "\n");
        }
      }
    }
    
    // end of view render
  }
  
  // Finalize rendering here & push the command buffer to the GPU
  if (!isCaptureRenderedTextureEnabled) {
    [commandBuffer commit];
  }
  
  return;
}

@end

