//
//  NAL.swift
//  CallbacksAndDelegates
//
//  Created by Patryk Maciąg on 13/07/2023.
//

import AVFoundation
import VideoToolbox

protocol SwifNALEncodedOutputDelegate {
    
    //Returns encoded CMSampleBuffer as NAL Unit
    func encodedDataOuput(_ encodedData: Data)
}

public final class SwifNAL {
    
    enum NaluType {
        case vcl
        case nonVcl
    }
    
    //MARK: - Properties
    private let naluStartCode = Data([0x00, 0x00, 0x00, 0x01])
    var encodedDataDelegate: SwifNALEncodedOutputDelegate?
    
    func isIframe(_ sbuf: CMSampleBuffer) -> Bool {
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
    
    func extractDataFromCMBlockBuffer(bbuf: CMBlockBuffer) {
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
            encodedDataDelegate?.encodedDataOuput(data)
            
            bufferOffset += AVCCHeaderLength + Int(NALUnitLength)
            
        }
    }
    
    ///Extracts Sequence Parameter Set and Picture Parameter set from CMSampleBuffer
    func extractSPSAndPPS(_ sbuf: CMSampleBuffer) {
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

        encodedDataDelegate?.encodedDataOuput(naluStartCode + Data(bytes: spsPtr, count: spsSize))
        encodedDataDelegate?.encodedDataOuput(naluStartCode + Data(bytes: ppsPtr, count: ppsSize))
    }
}
