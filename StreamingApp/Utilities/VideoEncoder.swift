//
//  H264Encoder.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

//https://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer

import AVFoundation
import VideoToolbox

protocol VideoEncoderOutputDelegate {
    //Returns encoded CMSampleBuffer as NAL Unit
    func encodedDataOuput(_ data: Data)
}

class VideoEncoder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let naluStartCode = Data([0x00, 0x00, 0x00, 0x01])
    var encodedDataDelegate: VideoEncoderOutputDelegate?
    private var compressionSession: VTCompressionSession!
    
    private func isIframe(_ sbuf: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: true) as? [[CFString: Any]]
        
        /*
         I-Frame's are synchronous, so we might encounter two scenarios when parsing CMSampleBufferGetSampleAttachmentsArray
         1.Key exist and has a value of:
            true    => Not an I-Frame
            false   => I-Frame
         2.Key does not exist => I-Frame
        */
        
        let keyExists = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        
        return !keyExists
    }
    
    private func extractDataFromCMBlockBuffer(bbuf: CMBlockBuffer) {
        var bufferLength: Int = 0
        var bufferDataPtr: UnsafeMutablePointer<Int8>?
        
        let error = CMBlockBufferGetDataPointer(
            bbuf,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &bufferLength,
            dataPointerOut: &bufferDataPtr
        )
        
        guard error == kCMBlockBufferNoErr, let bufferDataPtr = bufferDataPtr else { return }
        
        var bufferOffset: Int = 0
        let AVCCHeaderLength: Int = 4
        
        while bufferOffset < (bufferLength - AVCCHeaderLength) {
            var NALUnitLength: UInt32 = 0
            memcpy(&NALUnitLength, (bufferDataPtr + bufferOffset), AVCCHeaderLength)
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
            
            
            let data = Data(bytes: bufferDataPtr + bufferOffset + AVCCHeaderLength, count: Int(bufferLength))
            
            print("Sending Visal Data")
            encodedDataDelegate?.encodedDataOuput(naluStartCode + data)
            
            bufferOffset += AVCCHeaderLength + Int(NALUnitLength)
            
        }
    }
    
    ///Extracts Sequence Parameter Set and Picture Parameter set from CMSampleBuffer
    private func extractSPSAndPPS(_ sbuf: CMSampleBuffer) {
        //SPS and PPS is located in format description
        guard let formatDescriptoin = CMSampleBufferGetFormatDescription(sbuf) else { return }
        var parameterSetCount = 0
        
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescriptoin,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: nil
        )
        
        //The number of parameterSetCount to include in the format description must be at least 2.
        guard parameterSetCount >= 2 else { return }
        
        //Sequence Parameter Set
        var spsSize: Int = 0
        var spsPtr: UnsafePointer<UInt8>?
        
        //Picture Parameter Set
        var ppsSize: Int = 0
        var ppsPtr: UnsafePointer<UInt8>?
        
        //Extracting sps data
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescriptoin,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPtr,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        
        //Extracting pps data
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescriptoin,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPtr,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        
        guard let spsPtr = spsPtr, let ppsPtr = ppsPtr else { return }
        
        print("Sending -> SPS")
        encodedDataDelegate?.encodedDataOuput(naluStartCode + Data(bytes: spsPtr, count: spsSize))
        print("Sending -> PPS")
        encodedDataDelegate?.encodedDataOuput(naluStartCode + Data(bytes: ppsPtr, count: ppsSize))
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
        
        if encoder.isIframe(sampleBuffer) {
            encoder.extractSPSAndPPS(sampleBuffer)
        }
    
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        
        encoder.extractDataFromCMBlockBuffer(bbuf: blockBuffer)
    }
    
    func configureCompressionSession() {
        let width = Int32(562)
        let height = Int32(1218)
        
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

