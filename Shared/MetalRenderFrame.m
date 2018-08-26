//
//  MetalRenderFrame.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object contains references to Metal buffers that implement decoding
//  and rendering of data from a file.

#include "MetalRenderFrame.h"

#include "MetalRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
//#import "AAPLShaderTypes.h"

// Private API

@interface MetalRenderFrame ()

@end

// Main class performing the rendering
@implementation MetalRenderFrame

- (NSString*) description
{
#if defined(DEBUG)
  return [NSString stringWithFormat:@"renderFrame %p, isReadLocked %d : W x H %d x %d",
          self,
          (int)self.isReadLocked,
          (int)self.width,
          (int)self.height];
#else
  return [NSString stringWithFormat:@"renderFrame %p, W x H %d x %d",
          self,
          (int)self.width,
          (int)self.height];
#endif // DEBUG
  
}

@end

