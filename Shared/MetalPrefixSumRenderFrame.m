//
//  MetalPrefixSumRenderFrame.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object contains references to Metal buffers that implement decoding
//  and rendering of data from a file.

#include "MetalPrefixSumRenderFrame.h"

#include "MetalRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
//#import "AAPLShaderTypes.h"

// Private API

@interface MetalPrefixSumRenderFrame ()

@end

// Main class performing the rendering
@implementation MetalPrefixSumRenderFrame

- (NSString*) description
{
  return [NSString stringWithFormat:@"mpsRenderFrame %p : W x H %d x %d",
          self,
          (int)self.width,
          (int)self.height];
}

@end

