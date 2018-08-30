//
//  prefix_sum.h
//
//  Created by Mo DeJong on 6/3/18.
//  Copyright © 2018 helpurock. All rights reserved.
//
//  Inline methods that implement prefix sum on
//  array of uint8_t byte values.

#ifndef _prefix_sum_h
#define _prefix_sum_h

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

// Reduce sum byte values, pass the width and height
// of the reduced output array.

static inline
void PrefixSum_reduce(uint8_t *inBytes, int inNumBytes,
                      uint8_t *outBytes, int outNumBytes)
{
#if defined(DEBUG)
  assert((outNumBytes * 2) == inNumBytes);
#endif // DEBUG
  
  for ( int offset = 0; offset < outNumBytes; offset++ ) {
    // Transform output offset to pair of offsets in 2x larger array
    
    if (offset == 58) {
      offset = 58;
    }
    
    int offset2x = offset * 2;
    int offset2xPlusOne = offset2x + 1;
    
#if defined(DEBUG)
    assert(offset2x < inNumBytes);
    assert(offset2xPlusOne < inNumBytes);
#endif // DEBUG

    uint8_t in1 = inBytes[offset2x];
    uint8_t in2 = inBytes[offset2xPlusOne];
    
    uint8_t sumByte = in1 + in2;

#if defined(DEBUG)
    assert(offset < outNumBytes);
#endif // DEBUG
    outBytes[offset] = sumByte;
  }
}

// Prefix sum downsweep, read input texture1
// and previously reduced texture2.

static inline
void PrefixSum_downsweep(uint8_t *inBytes1, int inNumBytes1,
                         uint8_t *inBytes2, int inNumBytes2,
                         uint8_t *outBytes, int outNumBytes)
{
  const int debug = 0;
  
#if defined(DEBUG)
  assert((inNumBytes1 * 2) == outNumBytes);
  assert(outNumBytes == inNumBytes2);
#endif // DEBUG
  
  for ( int offset = 0; offset < outNumBytes; offset++ ) {
    // t1Offset is the offset in t1 that is read from unconditionally
    int t1Offset = offset / 2;
    
#if defined(DEBUG)
    assert(t1Offset < inNumBytes1);
#endif // DEBUG
    
    uint8_t t1Byte = inBytes1[t1Offset];
    
    // Second byte is loaded from inBytes2
    
    int t2Offset = offset - 1;
    
    uint8_t t2Byte;
    
    if ((offset & 0x1) == 0) {
      // even
      t2Byte = 0;
    } else {
      // odd
#if defined(DEBUG)
      assert(t2Offset < inNumBytes2);
#endif // DEBUG
      t2Byte = inBytes2[t2Offset];
    }
    
    uint8_t sumByte = t1Byte + t2Byte;
    
#if defined(DEBUG)
    assert(offset < outNumBytes);
#endif // DEBUG
    
    if (debug) {
      printf("t1 %d : inBytes1[%3d]\n", t1Byte, t1Offset);
      printf("t2 %d : inBytes2[%3d]\n", t2Byte, t2Offset);
      printf("outBytes[%3d] = %d\n", offset, sumByte);
    }
    
    outBytes[offset] = sumByte;
  }
}

// Simple serial exclusive prefix sum impl for unsigned byte values

static inline
void PrefixSum_exclusive(uint8_t *inBytes, int inNumBytes,
                      uint8_t *outBytes, int outNumBytes)
{
#if defined(DEBUG)
  assert(inNumBytes == outNumBytes);
#endif // DEBUG
  
  uint8_t byteSum = 0;
  
  for ( int offset = 0; offset < outNumBytes; offset++ ) {
#if defined(DEBUG)
    assert(offset < inNumBytes);
    assert(offset < outNumBytes);
#endif // DEBUG
    
    uint8_t inByte = inBytes[offset];
    outBytes[offset] = byteSum;
    byteSum += inByte;
  }
}

// Simple serial inclusive prefix sum impl for unsigned byte values

static inline
void PrefixSum_inclusive(uint8_t *inBytes, int inNumBytes,
                         uint8_t *outBytes, int outNumBytes)
{
#if defined(DEBUG)
  assert(inNumBytes == outNumBytes);
#endif // DEBUG
  
  uint8_t byteSum = 0;
  
  for ( int offset = 0; offset < outNumBytes; offset++ ) {
#if defined(DEBUG)
    assert(offset < inNumBytes);
    assert(offset < outNumBytes);
#endif // DEBUG
    
    uint8_t inByte = inBytes[offset];
    byteSum += inByte;
    outBytes[offset] = byteSum;
  }
}

#endif // _prefix_sum_h
