//
//  VideoDecoder.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 14/07/2023.
//

import Foundation
import AVFoundation

protocol VideoDecoderOutputDelegate {
    func decodedOutput(_ dataOutput: CMSampleBuffer)
}

/// Abstract: Object recives data comosed of NAL Units and converts them Into H264Format
class VideoDecoder {
    func convertNALUToH264Unit(_ NALU: Data) -> (H264Data: Data, H264Header: Data?) {
        let category = NALU[0] & 0x1F
        
        switch category {
        case 1...5: //When NAL Unit category is VCL
            var NALULength = CFSwapInt32HostToBig(UInt32(NALU.count))
            
            return (NALU, Data(bytes: &NALULength, count: 4))
        default: //When NAL Unit category is non-VCL
            return (NALU, nil)
        }
    }
    
    private var dataBuffer = Data()
    private let decodingQueue = DispatchQueue(label: "decoding.queue")
    var decodedDataDelegate: VideoDecoderOutputDelegate?
    
    private let NALUHeaderSize: Int = 4
    private var bufferIndex: Int = 0
    private var videoFormatDescription: CMVideoFormatDescription?
    
    private func createDescription(with H264Data: Data) {
    
        let spsPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: H264Data.count)
        H264Data.copyBytes(to: spsPtr, count: H264Data.count)
        
        let ppsPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: H264Data.count)
        H264Data.copyBytes(to: ppsPtr, count: H264Data.count)
                
        let parameterSet = [UnsafePointer(spsPtr), UnsafePointer(ppsPtr)]
        let parameterSetSizes = [H264Data.count, H264Data.count]
        
        defer {
            parameterSet.forEach {
                $0.deallocate()
            }
        }

        CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSet,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &videoFormatDescription
        )
        
    }
    
    private func createSampleBuffer(bbuf: CMBlockBuffer) -> CMSampleBuffer? {
        var sampleBuffer : CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        timingInfo.decodeTimeStamp = .invalid
        timingInfo.duration = CMTime.invalid
        timingInfo.presentationTimeStamp = .zero
        
        let error = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bbuf,
            formatDescription: videoFormatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard error == noErr, let sampleBuffer = sampleBuffer else {
            print("fail to create sample buffer")
            return nil
        }
        
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
                let dic = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(dic, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        
        return sampleBuffer
    }
    
    private func createBlockBuffer(with H264Unit: Data) -> CMBlockBuffer? {
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: H264Unit.count)
        
        H264Unit.copyBytes(to: pointer, count: H264Unit.count)
        var blockBuffer: CMBlockBuffer?
        
        let error = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: pointer,
            blockLength: H264Unit.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: H264Unit.count,
            flags: .zero,
            blockBufferOut: &blockBuffer
        )
        
        guard error == kCMBlockBufferNoErr else {
            print("fail to create block buffer")
            return nil
        }
        
        return blockBuffer
    }
    
    func decode(data: Data) {
        decodingQueue.async { [unowned self] in
            dataBuffer.append(data)
            
            while bufferIndex < (dataBuffer.endIndex - NALUHeaderSize) {
                //Using an OR oprater to check if data buffer cantains Nalu start code
                if dataBuffer[bufferIndex] | dataBuffer[bufferIndex + 1] | dataBuffer[bufferIndex + 2] | dataBuffer[bufferIndex + 3] == 1 {
                    if bufferIndex != 0 {
                        let H264Unit = convertNALUToH264Unit(Data(dataBuffer[0..<bufferIndex]))
                        //IF H264 unit was created from nonVCL (SPS, PPS, etc.) we must create description for it
                        if H264Unit.H264Header == nil { createDescription(with: H264Unit.H264Data) }
                        
                        if let blockBuffer = createBlockBuffer(with: H264Unit.H264Data), let sampleBuffer = createSampleBuffer(bbuf: blockBuffer) {
                            decodedDataDelegate?.decodedOutput(sampleBuffer)
                        }
                    }
                    
                    dataBuffer.removeSubrange(0..<bufferIndex + 3)
                    bufferIndex = 0
                } else {
                    bufferIndex += 1
                }
            }
        }
    }
    
}
