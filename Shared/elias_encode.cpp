//
//  elias_encode.cpp
//
//  Created by Mo DeJong on 6/4/18.
//  Copyright © 2018 helpurock. All rights reserved.
//

#include "elias_encode.h"
#include <assert.h>
#include "elias.hpp"

// Read n bytes from inBytePtr and emit n symbols with fixed bit width
// calculated from input power of 2 value k (0 = 1, 1 = 2, 2 = 4).
// The returned buffer is dynamically allocated with malloc() and
// must be released via free(). NULL is returned if memory cannot be allocted.

uint8_t* elias_gamma_encode(uint8_t *inBytePtr, int numBytes, int * numOutputBytes, int * numOutputBits)
{
    EliasGammaEncoder encoder;
    
    for (int i = 0; i < numBytes; i++) {
        uint8_t byteVal = inBytePtr[i];
        encoder.encode(byteVal);
    }
    encoder.finish();
    
    *numOutputBits = encoder.numEncodedBits;
    
    // Calculate number of encoded bits and compare to
    // output, these must match.
    
#if defined(DEBUG)
    int numBits = encoder.numBits(inBytePtr, numBytes);
    assert(numBits == *numOutputBits);
#endif // DEBUG
    
    int numEncodedBytes = (int) encoder.bytes.size();
    assert(numEncodedBytes > 0);
    *numOutputBytes = numEncodedBytes;
    
    uint8_t *encodedBytes = (uint8_t *) malloc(numEncodedBytes);
    if (encodedBytes == NULL) {
        return NULL;
    }
    
    uint8_t *outPtr = encodedBytes;
    for ( uint8_t byte : encoder.bytes ) {
        if (1) {
        printf("enc byte 0x%.2X\n", byte);
        }
        *outPtr++ = byte;
    }
    
#if defined(DEBUG)
    // Verify that decoding from this buffer of symbols produces
    // the same output.
    
    EliasGammaDecoder decoder;
    
    vector<uint8_t> decodedVec = decoder.decode(encoder.bytes);
    int cmp = memcmp(inBytePtr, decodedVec.data(), numBytes);
    assert(cmp == 0);
    
    assert(encoder.numEncodedBits == decoder.numDecodedBits);
#endif // DEBUG
    
    return encodedBytes;
}

// Decode symbols from inEncodedBytePtr buffer of length numInBytes.

uint8_t* elias_gamma_decode(uint8_t *inEncodedBytePtr, int numInBytes, int * numDecodedBytes, int * numDecodedBits)
{
    EliasGammaDecoder decoder;
    
    // FIXME: optimize to read directly instead of copy ??
    vector<uint8_t> inBytesVec(numInBytes);
    memcpy(inBytesVec.data(), inEncodedBytePtr, numInBytes);
    
    vector<uint8_t> decodeBytesVec = decoder.decode(inBytesVec);
    assert(decodeBytesVec.size() > 0);
    *numDecodedBytes = (int) decodeBytesVec.size();
    
    uint8_t *decodeBytes = (uint8_t *) malloc(*numDecodedBytes);
    if (decodeBytes == NULL) {
        return NULL;
    }
    
    // FIXME: how can return bytes not be copied again?
    memcpy(decodeBytes, decodeBytesVec.data(), *numDecodedBytes);
    
    *numDecodedBits = decoder.numDecodedBits;

    return decodeBytes;
}

// Return the number of bits needed to store this set of symbols

int elias_gamma_num_bits(uint8_t *inBytePtr, int n)
{
    EliasGammaEncoder encoder;
    return encoder.numBits(inBytePtr, n);
}
