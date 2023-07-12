//
//  H264Encoder.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

//https://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer

import AVFoundation
import VideoToolbox

class VideoEncoder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var compressionSession: VTCompressionSession!
    
    private static let naluStartCode = Data([UInt8](arrayLiteral: 0x00, 0x00, 0x00, 0x01))
    public var naluHandler: ((Data) -> Void)?
        
    private func extractSPSAndPPS(from sampleBuffer: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        var parameterSetCount = 0
        
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            description,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: nil
        )
        
        guard parameterSetCount == 2 else { return }
        
        var spsSize: Int = 0
        var sps: UnsafePointer<UInt8>?
        
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            description,
            parameterSetIndex: 0,
            parameterSetPointerOut: &sps,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        
        var ppsSize: Int = 0
        var pps: UnsafePointer<UInt8>?
        
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            description,
            parameterSetIndex: 1,
            parameterSetPointerOut: &pps,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        
        guard let sps = sps, let pps = pps else { return }
        
        print(#function)
        [Data(bytes: sps, count: spsSize), Data(bytes: pps, count: ppsSize)].forEach {
            print("$0 is \($0)")
            naluHandler?(VideoEncoder.naluStartCode + $0)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        encode(sbuf: sampleBuffer)
    }
    
    
    private func encode(sbuf buffer: CMSampleBuffer) {
        guard let compressionSession = compressionSession, let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let presenttationTimeStamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        let duration = CMSampleBufferGetDuration(buffer)
        
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presenttationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    private var compressionOutputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) in
        guard let outputCallbackRefCon = outputCallbackRefCon else { print("nil pointer"); return }
        guard status == noErr else { print("encoding failed"); return }
        guard infoFlags != .frameDropped else { print("Frames dropped"); return }
        
        guard let sampleBuffer = sampleBuffer else { print("nill buffer"); return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { print("Buffer not ready"); return }
        
        let encoder: VideoEncoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
        
        if sampleBuffer.isIFrame {
            encoder.extractSPSAndPPS(from: sampleBuffer)
        }
        
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }
        
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let error = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard error == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }
        var packageStartIndex = 0
            
        // dataPointer has several NAL units which respectively is
        // composed of 4 bytes data represents NALU length and pure NAL unit.
        // To reduce confusion, i call it a package which represents (4 bytes NALU length + NAL Unit)
        while packageStartIndex < totalLength {
            var nextNALULength: UInt32 = 0
            memcpy(&nextNALULength, dataPointer.advanced(by: packageStartIndex), 4)
            // First four bytes of package represents NAL unit's length in Big Endian.
            // We should convert Big Endian Representation to Little Endian becasue
            // nextNALULength variable here should be representation of human readable number.
            nextNALULength = CFSwapInt32BigToHost(nextNALULength)
            
            var nalu = Data(bytes: dataPointer.advanced(by: packageStartIndex+4), count: Int(nextNALULength))
            
            packageStartIndex += (4 + Int(nextNALULength))
            
            encoder.naluHandler?(VideoEncoder.naluStartCode + nalu)
        }
        
        print("Recived data")
        
    }
    
    func configureCompressionSession() {
        let width = Int32(720)
        let height = Int32(1280)
        
        let error = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: kCFAllocatorDefault,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard error == errSecSuccess, let compressionSession = compressionSession else {
            print("failed to configure")
            return
        }
        
        let propertyDictionary = [
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Baseline_AutoLevel,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 60,
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_Quality: 0.5
        ] as [CFString : Any] as CFDictionary
        
        guard VTSessionSetProperties(compressionSession, propertyDictionary: propertyDictionary) == noErr else { print("Cound not set settings"); return }
        guard VTCompressionSessionPrepareToEncodeFrames(compressionSession) == noErr else { print("Could not prepare for encoding"); return }
    }
    
    override init() {
        super.init()
    }
    
}

