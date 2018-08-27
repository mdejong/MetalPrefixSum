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
void PrefisSum_reduce(uint8_t *inBytes, int inNumBytes,
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

#endif // _prefix_sum_h
