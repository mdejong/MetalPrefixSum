//
//  elias_encode.h
//
//  Created by Mo DeJong on 6/4/18.
//  Copyright © 2018 helpurock. All rights reserved.
//

#ifndef elias_encode_h
#define elias_encode_h

#include <stdlib.h>

// Encode N byte symbols into and output buffer of at least n.
// Returns the number of bytes written to encodedBytes, this
// number of bytes should be less than the original???

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// Read n bytes from inBytePtr and emit n symbols with fixed bit width
// calculated from input power of 2 value k (0 = 1, 1 = 2, 2 = 4).
// The returned buffer is dynamically allocated with malloc() and
// must be released via free(). NULL is returned if memory cannot be allocted.
    
uint8_t* elias_gamma_encode(uint8_t *inBytePtr, int n, int * numOutputBytes, int * numOutputBits);

// Decode symbols from inEncodedBytePtr buffer of length numInBytes.
    
uint8_t* elias_gamma_decode(uint8_t *inEncodedBytePtr, int numInBytes, int * numDecodedBytes, int * numDecodedBits);

// Return the number of bits needed to store this set of symbols
    
int elias_gamma_num_bits(uint8_t *inBytePtr, int n);
    
#ifdef __cplusplus
}
#endif // __cplusplus

#endif // elias_encode_h
