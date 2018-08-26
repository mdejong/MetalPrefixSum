# MetalElias

A GPU based Elias gamma decoder for iOS on top of Metal, adapted from Basic Texturing example provided by Apple. This decoder is known to work on iOS and should work on other Metal capable hardware. 

## Overview

This project is adapted from a Metal huffman implementation. See [MetalHuffman] https://github.com/mdejong/MetalHuffman

## Status

This encoder/decoder implementation of GPU based Elias gamma decoding is a test of parallel block based decoding speed.

## Decoding Speed

Please note that current results indicate decoding on the CPU is significantly faster than decoding on the GPU, since each decoding step in a block has to wait until the previous one has completed. Processing blocks in parallel does not appear to be competitive when compared to executing on the CPU.

## Implementation

See AAPLRenderer.m and AAPLShaders.metal for the core GPU rendering logic. An inlined and branch free Elias gamma decoder is included.

