//
//  elias.hpp
//
//  Created by Mo DeJong on 6/3/18.
//  Copyright © 2018 helpurock. All rights reserved.
//
//  The elias coder provides elias gamma encoding for
//  residual values that are non-zero and near zero.

#ifndef elias_hpp
#define elias_hpp

#include <stdio.h>
#include <assert.h>

#include <cinttypes>
#include <vector>
#include <bitset>

using namespace std;

static inline
void EliasGamma_printBits16(unsigned int x, string tag)
{
    printf("%s\n", tag.c_str());
    printf("0b");
    for ( int i = 15; i >= 0; i-- ) {
        bool b = ((x >> i) & 0x1) != 0;
        printf("%d", (int)b);
    }
    printf("\n");
}

// Optimized symbol bit width calculation, this logic
// looks at a binary number like 0b00010101 and calculates
// the number of trailing zeros leading up to the first 1 (MSB)
// as 3 zeros -> 5 bits.

static inline
int
EliasGamma_bitWidth(uint8_t symbol) {
    // MSB
    
    // input to __builtin_clz is treated as unsigned
    // 32 bit number, so always subtract 16.
    unsigned int symbolPlusOne = ((unsigned int)symbol) + 1;
#if defined(DEBUG)
    assert(symbolPlusOne >= 1 && symbolPlusOne <= 256);
#endif // DEBUG
    unsigned int countOfZeros = __builtin_clz(symbolPlusOne) - 16;
#if defined(DEBUG)
    assert(countOfZeros != 0);
    assert(countOfZeros <= 15);
#endif // DEBUG
    unsigned int highBitPosition = 16 - countOfZeros - 1;
#if defined(DEBUG)
    assert(highBitPosition >= 0 && highBitPosition <= 9);
    if (symbolPlusOne == 256) {
        assert(highBitPosition == 8);
    } else {
        assert(highBitPosition >= 0 && highBitPosition <= 7);
    }
#endif // DEBUG
    int totalBits = highBitPosition + 1 + highBitPosition;
    return totalBits;
}

class EliasGammaEncoder
{
    public:
    bitset<8> bits;
    unsigned int bitOffset;
    vector<uint8_t> bytes;
    unsigned int numEncodedBits;
    bool emitPaddingZeros;
    bool emitMSB;
    
    EliasGammaEncoder()
    : bitOffset(0), numEncodedBits(0), emitPaddingZeros(false), emitMSB(false) {
        bytes.reserve(1024);
    }
    
    void reset() {
        bits.reset();
        bitOffset = 0;
        bytes.clear();
        numEncodedBits = 0;
    }
    
    // This internal method writes bits as a byte
    
    void emitBitsAsByte() {
        const bool debug = false;
        
        uint8_t byteVal = 0;
        
        // Flush 8 bits to backing array of bytes.
        // Note that bits can be written as either
        // LSB first (reversed) or MSB first (not reversed).
        
        if (emitMSB) {
            for ( int i = 0; i < 8; i++ ) {
                unsigned int v = (bits.test(i) ? 0x1 : 0x0);
                byteVal |= (v << (7 - i));
            }
        } else {
            for ( int i = 0; i < 8; i++ ) {
                unsigned int v = (bits.test(i) ? 0x1 : 0x0);
                byteVal |= (v << i);
            }
        }
        
        bits.reset();
        bitOffset = 0;
        
        if (debug) {
            printf("emitBitsAsByte() emit byte 0x%02X\n", byteVal);
            EliasGamma_printBits16(byteVal, "byte");
        }
        
        bytes.push_back(byteVal);
        
        return;
    }
    
    void encodeBit(bool bit) {
        bits.set(bitOffset++, bit);
        
        if (bitOffset == 8) {
            numEncodedBits += 8;
            emitBitsAsByte();
        }
    }
    
    // Find the highest bit position that is on, return -1 when no on bit is found.
    // Note that this method cannot process the value zero and it supports the
    // range (1, 256) which corresponds to bit positions (0, 8) or 9 bits max,
    
    int highBitPosition(uint32_t number) {
        int highBitValue = -1;
        
        // The maximum value that is acceptable is 256 or 2^8
        // which falls outside the first byte.
        
        for (int i = 0; i < 9; i++) {
            if ((number >> i) & 0x1) {
                highBitValue = i;
            }
        }
        
#if defined(DEBUG)
        // In DEBUG mode, bits contains bits for this specific symbol.
        assert(highBitValue != -1);
#endif // DEBUG
        
#if defined(DEBUG)
        // Verify that this result matches EliasGamma_bitWidth() output
        // by passing the original input numer.
        {
            int bitWidth = (highBitValue * 2) + 1;
            int originalNumber = number - 1;
            int expectedBitWidth = EliasGamma_bitWidth(originalNumber);
            assert(bitWidth == expectedBitWidth);
        }
#endif // DEBUG
        
        return highBitValue;
    }
    
    // Encode unsigned byte range number (0, 255) with an
    // elias gamma encoding that implicitly adds 1 before encoding.
    
    void encode(uint8_t inByteNumber)
    {
        const bool debug = false;
        
#if defined(DEBUG)
        // In DEBUG mode, bits contains bits for this specific symbol.
        vector<bool> bitsThisSymbol;
#endif // DEBUG
        
        // The input value range is (0, 255) corresponding to (1, 256)
        // but since 0 is unused and 256 cannot be represented as uint8_t
        // always implicitly add 1 before encoding.
        
        uint32_t number = inByteNumber;
        number += 1;
        
        // highBitValue is set to highest POT (bit that is on) in unsigned number n
        // Encode highBitValue in unary; that is, as N zeroes followed by a one.
        
        int highBitValue = highBitPosition(number);
        
        if (debug) {
            printf("for n %3d : high bit value is 0x%02X aka %d\n", number, highBitValue, (0x1 << highBitValue));
        }
        
        // Emit highBitValue number of zero bits (unary)
        
        for (int i = 0; i < highBitValue; i++) {
            encodeBit(false);
#if defined(DEBUG)
            bitsThisSymbol.push_back(false);
#endif // DEBUG
        }
        
        encodeBit(true);
#if defined(DEBUG)
        bitsThisSymbol.push_back(true);
#endif // DEBUG
        
        // Emit the remaninig bits of the number n.
        
        for (int i = highBitValue - 1; i >= 0; i--) {
            bool bit = (((number >> i) & 0x1) != 0);
            encodeBit(bit);
#if defined(DEBUG)
            bitsThisSymbol.push_back(bit);
#endif // DEBUG
        }
        
        if (debug) {
#if defined(DEBUG)
            // Print bits that were emitted for this symbol,
            // note the order from least to most significant
            printf("bits for symbol (least -> most): ");
            
            for ( bool bit : bitsThisSymbol ) {
                printf("%d", bit ? 1 : 0);
            }
            printf("\n");
#endif // DEBUG
        }
    }
    
    // If any bits still need to be emitted, emit final byte.
    
    void finish() {
        if (bitOffset > 0) {
            // Flush 1-8 bits to some external output.
            // Note that all remaining bits must
            // be flushed as true so that multiple
            // symbols are not encoded at the end
            // of the buffer.
            
            numEncodedBits += bitOffset;
            
            // Emit zeros up until the end of a byte, so
            // the decoding logic will skip zeros until
            // the end of the stream and exit loop.
            
            while (bitOffset < 8) {
                bits.set(bitOffset++, false);
            }
            
            emitBitsAsByte();
        }
        
        // Emit two addition bytes that contain all zeros
        // so that any byte read can always read 2 bytes ahead
        // without going past the end of the valid buffer.
        
        if (emitPaddingZeros) {
            bytes.push_back(0);
            bytes.push_back(0);
        }
    }
    
    // Encode N symbols and emit any leftover bits
    
    void encode(const uint8_t * byteVals, int numByteVals) {
        for (int i = 0; i < numByteVals; i++) {
            uint8_t byteVal = byteVals[i];
            encode(byteVal);
        }
        finish();
    }
    
    // Query number of bits needed to store symbol
    // with the given k parameter. Note that this
    // size query logic does not need to actually copy
    // encoded bytes so it is much faster than encoding.
    
    int numBits(uint8_t inByteNumber) {
        //        uint32_t number = inByteNumber;
        //        number += 1;
        //#if defined(DEBUG)
        //        assert(number >= 1 && number <= 256);
        //#endif // DEBUG
        //        int highBitValue = highBitPosition(number);
        //        int lowBits = highBitValue;
        //        int totalBits = highBitValue + 1 + lowBits;
        //        return totalBits;
        
        return EliasGamma_bitWidth(inByteNumber);
    }
    
    // Query the number of bits needed to store these symbols
    
    int numBits(const uint8_t * byteVals, int numByteVals) {
        int numBitsTotal = 0;
        for (int i = 0; i < numByteVals; i++) {
            uint8_t byteVal = byteVals[i];
            numBitsTotal += numBits(byteVal);
        }
        return numBitsTotal;
    }
    
};

class EliasGammaDecoder
{
    public:
    bitset<8> bits;
    unsigned int bitOffset;
    vector<uint8_t> bytes;
    unsigned int byteOffset;
    unsigned int numDecodedBits;
    bool isFinishedReading;
    
    EliasGammaDecoder()
    {
        reset();
    }
    
    void reset() {
        numDecodedBits = 0;
        byteOffset = 0;
        bitOffset = 8;
        isFinishedReading = false;
    }
    
    bool decodeBit() {
        const bool debug = false;
        
        if (debug) {
            printf("decodeBit() bitOffset %d\n", bitOffset);
        }
        
        if (bitOffset == 8) {
            if (byteOffset == bytes.size()) {
                // All bytes read and all bits read
                isFinishedReading = true;
                return true;
            }
            
            bits.reset();
            
            uint8_t byteVal = bytes[byteOffset++];
            for ( int i = 0; i < 8; i++ ) {
                bool bit = ((byteVal >> i) & 0x1) ? true : false;
                bits.set(i, bit);
            }
            
            bitOffset = 0;
        }
        
        bool bit = bits.test(bitOffset++);
        
        if (debug) {
            printf("decodeBit() returning %d\n", bit);
        }
        
        return bit;
    }
    
    // Decode symbols from a buffer of encoded bytes and
    // return the results as a vector of decoded bytes.
    
    vector<uint8_t> decode(const vector<uint8_t> & inBytesVec) {
        reset();
        
        const bool debug = false;
        
        vector<uint8_t> decodedBytes;
        
        assert(inBytesVec.size() > 0);
        bytes.resize(inBytesVec.size());
        memcpy(bytes.data(), inBytesVec.data(), inBytesVec.size());
        
        for ( ; 1 ; ) {
            unsigned int countOfZeros = 0;
            
            while (decodeBit() == false) {
                countOfZeros++;
            }
            unsigned int symbol = (0x1 << countOfZeros);
            
            if (debug) {
                printf("symbol base : 2 ^ %d : %d\n", countOfZeros, symbol);
            }
            
            for ( int i = countOfZeros - 1; i >= 0; i-- ) {
                bool b = decodeBit();
                symbol |= ((b ? 1 : 0) << i);
            }
            
            if (isFinishedReading) {
                break;
            }
            
            if (debug) {
                printf("append decoded symbol = %d\n", symbol);
            }
            
#if defined(DEBUG)
            assert(symbol >= 1 && symbol <= 256);
#endif // DEBUG
            
            decodedBytes.push_back(symbol - 1);
            
            int highBitValue = countOfZeros;
            int lowBits = highBitValue;
            int totalBits = highBitValue + 1 + lowBits;
            numDecodedBits += totalBits;
        }
        
        return decodedBytes;
    }
    
};

// This optimized decoder takes advantage of the limited range of input
// values (0,255) -> (1,256) so that in the special case where bit
// 9 is true then this indicates a special case where the original
// value can only be 256 where all the bits after the 9th bit would
// be zero. The optimization is that since the special case can be
// detected by a 16 bit buffer that contains 0x0100. This means the
// 17th bit need not be read and so the entire test can be done with
// a 16 bit register.

class EliasGammaDecoderOpt16
{
    public:
    
    EliasGammaDecoderOpt16()
    {
    }
    
    // Optimized symbol decode logic that reads a known number of symbols
    // from inBytesVec with 16 bit register implementation that counts
    // leading zeros for branchless operation.
    
    void decode(const uint8_t * encodedBitsPtr,
                unsigned int numSymbols,
                vector<uint8_t> & outBytesVec)
    {
        const bool debug = false;
        
        if (outBytesVec.size() != numSymbols) {
            outBytesVec.resize(numSymbols);
        }
        uint8_t *decodedBytesPtr = outBytesVec.data();
        
        unsigned int currentNumBits = 0;
        
        for ( ; 1 ; ) {
            if (numSymbols == 0) {
                break;
            }
            
            // Shift to adjust into 16 bit buffer based
            // on the number of bits has been consumed.
            
            const unsigned int numBitsInByte = 8;
            unsigned int numBytesRead = (currentNumBits / numBitsInByte);
            unsigned int numBitsReadMod8 = (currentNumBits % numBitsInByte);
            
            if (debug) {
                printf("currentNumBits %d : numBitsReadMod8 %d\n", numBytesRead, numBitsReadMod8);
            }
            
            unsigned int inputBitPattern = 0; // 16 bits used
            
            // Unconditionally read 3 bytes
            
            unsigned int b0 = encodedBitsPtr[numBytesRead];
            unsigned int b1 = encodedBitsPtr[numBytesRead+1];
            unsigned int b2 = encodedBitsPtr[numBytesRead+2];
            
            if (debug) {
                printf("read offsets : %d %d %d\n", numBytesRead, numBytesRead+1, numBytesRead+2);
                printf("read (b0, b1, b2) 0x%02X 0x%02X 0x%02X\n", b0, b1, b2);
            }
            
            // MSB
            
            // Left shift the already consumed bits off left side of b0
            b0 <<= numBitsReadMod8;
            b0 &= 0xFF;
            inputBitPattern = b0 << 8;
            
            // Left shift the 8 bits in b1 then OR into inputBitPattern
            inputBitPattern |= b1 << numBitsReadMod8;
            
            // Right shift b2 to throw out unused bits
            b2 >>= (8 - numBitsReadMod8);
            inputBitPattern |= b2;
            
            if (debug) {
                EliasGamma_printBits16(inputBitPattern, "inputBitPattern");
            }
            
            // CTZ is count of zeros from least significant bit
            
            unsigned int countOfZeros;
            unsigned int bitsThisSymbol;
            unsigned int symbol;
            
            // MSB
            // input to __builtin_clz is treated as unsigned
            // 32 bit number, so always subtract 16.
            countOfZeros = __builtin_clz((unsigned int)inputBitPattern) - 16;
            
            bitsThisSymbol = ((countOfZeros << 1) + 1); // ((countOfZeros * 2) + 1)
            currentNumBits += bitsThisSymbol;
            
            // Shift left to place MSB of value at the MSB of
            // 16 bit register.
            
            unsigned int shiftedLeft = inputBitPattern << countOfZeros;
            
            if (debug) {
                EliasGamma_printBits16(shiftedLeft, "shiftedLeft");
            }
            
            // Shift right to place MSB of value at correct bit offset
            
            unsigned int shiftedRight = shiftedLeft >> (16 - (countOfZeros+1));
            
            if (debug) {
                EliasGamma_printBits16(shiftedRight, "shiftedRight");
            }
            
            symbol = shiftedRight;
            
            if (debug) {
                printf("append decoded symbol = %d\n", symbol);
            }
            
            numSymbols -= 1;
            
#if defined(DEBUG)
            assert(symbol >= 1 && symbol <= 256);
#endif // DEBUG
            *decodedBytesPtr++ = (symbol - 1);
        }
        
        return;
    }
    
};

#endif // elias_hpp
