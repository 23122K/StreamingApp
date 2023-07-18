//
//  AudioEncoder.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 12/07/2023.
//

import AVFoundation
import AudioToolbox

protocol AudioEncoderOutputDelegate {
    func encodedDataOuput(_ sampleBuffer: CMSampleBuffer)
}

// AVFoundation on iOS systems is missing audioDataOutput.audioSettings, wchich wolud do most of the work for us encoding audio to ACC but it does not exist

class AudioEncoder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let encodingQueue = DispatchQueue(label: "encoding.queue")
    var delegate: AudioEncoderOutputDelegate?
    
    private var inSourceFormat: AudioStreamBasicDescription?
    
    private var _inDestinationFormat: AudioStreamBasicDescription?
    private var inDestinationFormat: AudioStreamBasicDescription {
        get {
            if _inDestinationFormat == nil {
                var basicDescription = AudioStreamBasicDescription()
            
                basicDescription.mChannelsPerFrame = channels
                basicDescription.mSampleRate = sampleRate
                basicDescription.mFormatID = kAudioFormatMPEG4AAC
                basicDescription.mBitsPerChannel = 0
                basicDescription.mFormatFlags = 0
                basicDescription.mBytesPerPacket = 0
                basicDescription.mFramesPerPacket = samplesPerFrame
                basicDescription.mReserved = 0
                
                _inDestinationFormat = basicDescription
            }
            
            return _inDestinationFormat!
        }
        
        set { _inDestinationFormat = newValue }
    }
    
    private var _audioConverter: AudioConverterRef?
    private var audioConverter: AudioConverterRef {
        var status: OSStatus = noErr
        var audioConverter: AudioConverterRef?
        
        status = AudioConverterNewSpecific(
            &inSourceFormat!,
            &inDestinationFormat,
            inClassDescriptionsSize,
            &inClassDescriptions,
            &audioConverter
        )
        
        _audioConverter = audioConverter
        if status == noErr { print("STATUS noErr in audioConverter")}
        return _audioConverter!
    }
    
    private var formatDescription: CMFormatDescription?
    private var currentBufferList: UnsafeMutableAudioBufferListPointer?
    
    private var inClassDescriptions: Array<AudioClassDescription> = [
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleHardwareAudioCodecManufacturer),
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleSoftwareAudioCodecManufacturer),
    ]
    private var inClassDescriptionsSize: UInt32 {
        UInt32(inClassDescriptions.count)
    }
    
    private let channels: UInt32 = 1
    private let sampleRate: Double = 44100
    private let sampleSize: UInt32 = 1024 //1024 is a default ACC buffer size
    private let samplesPerFrame: UInt32 = 1024
    
    private let audioBufferListSize = MemoryLayout<AudioBufferList>.size
    
    func onInputDataForAudioConverter(_ ioNumberDataPackets:UnsafeMutablePointer<UInt32>, ioData:UnsafeMutablePointer<AudioBufferList>, outDataPacketDescription:UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {

        guard let bufferList:UnsafeMutableAudioBufferListPointer = currentBufferList else {
            ioNumberDataPackets.pointee = 0
            return -1
        }

        memcpy(ioData, bufferList.unsafePointer, audioBufferListSize)
        ioNumberDataPackets.pointee = 1
        free(bufferList.unsafeMutablePointer)
        currentBufferList = nil

        return noErr
    }
    
    fileprivate var inputDataProc:AudioConverterComplexInputDataProc = {(
        converter:AudioConverterRef,
        ioNumberDataPackets:UnsafeMutablePointer<UInt32>,
        ioData:UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription:UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
        inUserData:UnsafeMutableRawPointer?) in
        return unsafeBitCast(inUserData, to: AudioEncoder.self).onInputDataForAudioConverter(
            ioNumberDataPackets,
            ioData: ioData,
            outDataPacketDescription: outDataPacketDescription
        )
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = sampleBuffer.formatDescription else { return }
        
        inSourceFormat = formatDescription.audioStreamBasicDescription
        
        var blockBuffer: CMBlockBuffer?
        var inAudioBufferList: AudioBufferList = AudioBufferList()
        currentBufferList = AudioBufferList.allocate(maximumBuffers: 1)
        
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &inAudioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        var ioOutputDataPacketSize:UInt32 = 1
        let dataLength:Int = CMBlockBufferGetDataLength(blockBuffer!)
        let outOutputData:UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
        outOutputData[0].mNumberChannels = inDestinationFormat.mChannelsPerFrame
        outOutputData[0].mDataByteSize = UInt32(dataLength)
        outOutputData[0].mData = malloc(dataLength)
        
        let status:OSStatus = AudioConverterFillComplexBuffer(
            audioConverter,
            inputDataProc,
            unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
            &ioOutputDataPacketSize,
            outOutputData.unsafeMutablePointer,
            nil
        )
        
        if (0 <= status && ioOutputDataPacketSize == 1) {
            var result: CMSampleBuffer?
            var timing: CMSampleTimingInfo = CMSampleTimingInfo()
            let numSamples: CMItemCount = sampleBuffer.numSamples
            
            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: nil,
                dataReady: false,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleCount: numSamples,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &result
            )
            
            
            CMSampleBufferSetDataBufferFromAudioBufferList(
                result!,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: 0,
                bufferList: outOutputData.unsafePointer
            )
            
            delegate?.encodedDataOuput(result!)
        }
        
    }
}


