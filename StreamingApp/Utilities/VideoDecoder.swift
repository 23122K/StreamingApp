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
/// https://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream
/// https://stackoverflow.com/questions/25078364/cmvideoformatdescriptioncreatefromh264parametersets-issues
class VideoDecoder {
    
    enum naluType {
        case vcl
        //case sei // nonVcl (6)
        case sps // nonVcl (7)
        case pps // nonVcl (8)
        case nonVcl
        
    }
    
    //MARK: - Properties
    //When pps and sps units are not nil we can create CMVideoFormatDescriptionCreateFromH264ParameterSets from them
    private var pps: Data?
    private var sps: Data?
    
    private var videoFormatDescription: CMVideoFormatDescription?
    
    private var dataBuffer = Data()
    private let decodingQueue = DispatchQueue(label: "decoding.queue")
    public var decodedDataDelegate: VideoDecoderOutputDelegate?
    
    private let naluStartCodeLength: Int = 4
    private var bufferIndex: Int = 0
    
    // Takes NAL unit as a parameter and replaces its start code with AVCC 4-bit header describing NAL unit length
    // Exception are SPS and PPS units which we have to leave unchanged
    // AVVC header must be swapped from little-endian to big-endian
    func convertNaluToAvcc(_ nalu: Data) -> (data: Data, type: naluType) {
        let type = nalu[0] & 0x1F
        
        switch type {
        case 1...5:
            var naluLength = CFSwapInt32HostToBig(UInt32(nalu.count))
            let naluLengthData = Data(bytes: &naluLength, count: naluStartCodeLength)
            return (naluLengthData + nalu, .vcl)
        case 7:
            sps = nalu
            return (nalu, .sps)
        case 8:
            pps = nalu
            return (nalu, .pps)
        default:
            var naluLength = CFSwapInt32HostToBig(UInt32(nalu.count))
            let naluLengthData = Data(bytes: &naluLength, count: naluStartCodeLength)
            return (naluLengthData + nalu, .nonVcl)
        }
    }

    // Creates CMVideoFormatDescriptionCreateFromH264ParameterSets from sps and pps property if they exists
    private func createDescription() {
        guard let pps = pps, let sps = sps else { return }
        
        let spsPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: sps.count)
        let ppsPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: pps.count)
        
        sps.copyBytes(to: spsPtr, count: sps.count)
        pps.copyBytes(to: ppsPtr, count: pps.count)
                
        let parameterSet = [UnsafePointer(spsPtr), UnsafePointer(ppsPtr)]
        let parameterSetSizes = [sps.count, pps.count]
        
        defer {
            for parameter in parameterSet { parameter.deallocate() }
            self.sps = nil
            self.pps = nil
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
        
        guard error == noErr, let sampleBuffer = sampleBuffer else { return nil }
        
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
                let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dictionary,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
        }
        
        return sampleBuffer
    }
    
    private func createBlockBuffer(with data: Data) -> CMBlockBuffer? {
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        
        data.copyBytes(to: pointer, count: data.count)
        var blockBuffer: CMBlockBuffer?
        
        let error = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: pointer,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: .zero,
            blockBufferOut: &blockBuffer
        )
        
        guard error == kCMBlockBufferNoErr else { return nil }
        
        return blockBuffer
    }
    
    func decode(data: Data) {
        decodingQueue.async { [unowned self] in
            dataBuffer.append(data)
            
            while bufferIndex < (dataBuffer.count - naluStartCodeLength) {
                // Using OR bit operation to check whether data buffer contains nal unit start code
                if dataBuffer[bufferIndex] | dataBuffer[bufferIndex + 1] | dataBuffer[bufferIndex + 2] | dataBuffer[bufferIndex + 3] == 1 {
                    if bufferIndex != 0 {
                        let convertedNalUnit = convertNaluToAvcc(Data(dataBuffer[0..<bufferIndex]))
                        
                        switch convertedNalUnit.type {
                        case .vcl, .nonVcl:
                            if let blockBuffer = createBlockBuffer(with: convertedNalUnit.data), let sampleBuffer = createSampleBuffer(bbuf: blockBuffer) {
                                decodedDataDelegate?.decodedOutput(sampleBuffer)
                            }
                        case .sps, .pps:
                            videoFormatDescription = nil
                            createDescription()
                        }
                    }
                    
                    dataBuffer.removeSubrange(0..<bufferIndex + naluStartCodeLength)
                    bufferIndex = 0
                } else {
                    bufferIndex += 1
                }
            }
        }
    }

    
}



