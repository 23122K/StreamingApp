import Foundation
import AVFoundation

protocol AudioEncoderDelegate: class {
    func didSetFormatDescription(audio formatDescription:CMFormatDescription?)
    func sampleOutput(audio sampleBuffer: CMSampleBuffer)
}

// MARK: -
/**
 - seealse:
  - https://developer.apple.com/library/ios/technotes/tn2236/_index.html
  - https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html
 */
final class AACEncoder: NSObject {
    static let packetSize:UInt32 = 1
    static let sizeOfUInt32:UInt32 = UInt32(MemoryLayout<UInt32>.size)
    static let framesPerPacket:UInt32 = 1024

    static let defaultProfile:UInt32 = UInt32(MPEG4ObjectID.AAC_LC.rawValue)
    static let defaultBitrate:UInt32 = 32 * 1024
    // 0 means according to a input source
    static let defaultChannels:UInt32 = 0
    // 0 means according to a input source
    static let defaultSampleRate:Double = 0
    static let defulatMaximumBuffers:Int = 1
    static let defaultBufferListSize:Int = AudioBufferList.sizeInBytes(maximumBuffers: 1)
    #if os(iOS)
    static let defaultInClassDescriptions:[AudioClassDescription] = [
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleSoftwareAudioCodecManufacturer),
        AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleHardwareAudioCodecManufacturer)
    ]
    #else
    static let defaultInClassDescriptions:[AudioClassDescription] = [
    ]
    #endif

    var muted:Bool = false

    var profile:UInt32 = AACEncoder.defaultProfile
    var channels:UInt32 = AACEncoder.defaultChannels
    var sampleRate:Double = AACEncoder.defaultSampleRate
    var inClassDescriptions:[AudioClassDescription] = AACEncoder.defaultInClassDescriptions
    var formatDescription:CMFormatDescription? = nil {
        didSet {
            if (!CMFormatDescriptionEqual(formatDescription, otherFormatDescription: oldValue)) {
                delegate?.didSetFormatDescription(audio: formatDescription)
            }
        }
    }
    var lockQueue:DispatchQueue = DispatchQueue(
        label: "com.github.shogo4405.lf.AACEncoder.lock", attributes: []
    )
    weak var delegate:AudioEncoderDelegate?
    internal(set) var running:Bool = false
    fileprivate var maximumBuffers:Int = AACEncoder.defulatMaximumBuffers
    fileprivate var bufferListSize:Int = AACEncoder.defaultBufferListSize
    fileprivate var currentBufferList:UnsafeMutableAudioBufferListPointer? = nil
    fileprivate var inSourceFormat:AudioStreamBasicDescription? {
        didSet {
            guard let inSourceFormat:AudioStreamBasicDescription = self.inSourceFormat else {
                return
            }
            let nonInterleaved:Bool = inSourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            maximumBuffers = nonInterleaved ? Int(inSourceFormat.mChannelsPerFrame) : AACEncoder.defulatMaximumBuffers
            bufferListSize = nonInterleaved ? AudioBufferList.sizeInBytes(maximumBuffers: maximumBuffers) : AACEncoder.defaultBufferListSize
        }
    }
    fileprivate var _inDestinationFormat:AudioStreamBasicDescription?
    var inDestinationFormat:AudioStreamBasicDescription {
        get {
            if (_inDestinationFormat == nil) {
                _inDestinationFormat = AudioStreamBasicDescription()
                _inDestinationFormat!.mSampleRate = 44100
                _inDestinationFormat!.mFormatID = kAudioFormatMPEG4AAC
                _inDestinationFormat!.mFormatFlags = profile
                _inDestinationFormat!.mBytesPerPacket = 0
                _inDestinationFormat!.mFramesPerPacket = AACEncoder.framesPerPacket
                _inDestinationFormat!.mBytesPerFrame = 0
                _inDestinationFormat!.mChannelsPerFrame = 1
                _inDestinationFormat!.mBitsPerChannel = 0
                _inDestinationFormat!.mReserved = 0

                CMAudioFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault, asbd: &_inDestinationFormat!, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription
                )
            }
            return _inDestinationFormat!
        }
        set {
            _inDestinationFormat = newValue
        }
    }

    fileprivate var inputDataProc:AudioConverterComplexInputDataProc = {(
        converter:AudioConverterRef,
        ioNumberDataPackets:UnsafeMutablePointer<UInt32>,
        ioData:UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription:UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
        inUserData:UnsafeMutableRawPointer?) in
        return unsafeBitCast(inUserData, to: AACEncoder.self).onInputDataForAudioConverter(
            ioNumberDataPackets,
            ioData: ioData,
            outDataPacketDescription: outDataPacketDescription
        )
    }

    fileprivate var _converter:AudioConverterRef?
    var converter:AudioConverterRef {
        var status:OSStatus = noErr
        if (_converter == nil) {
            var converter:AudioConverterRef? = nil
            status = AudioConverterNewSpecific(
                &inSourceFormat!,
                &inDestinationFormat,
                UInt32(inClassDescriptions.count),
                &inClassDescriptions,
                &converter
            )
            
            _converter = converter
        }
        if (status != noErr) {
            print("noErr")
        }
        return _converter!
    }

    func encodeSampleBuffer(_ sampleBuffer:CMSampleBuffer) {
        guard let format:CMAudioFormatDescription = sampleBuffer.formatDescription else {
            return
        }

        if (inSourceFormat == nil) {
            inSourceFormat = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        }

        var blockBuffer:CMBlockBuffer? = nil
        currentBufferList = AudioBufferList.allocate(maximumBuffers: maximumBuffers)
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: currentBufferList!.unsafeMutablePointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        if (muted) {
            for i in 0..<currentBufferList!.count {
                memset(currentBufferList![i].mData, 0, Int(currentBufferList![i].mDataByteSize))
            }
        }

        var ioOutputDataPacketSize:UInt32 = 1
        let dataLength:Int = CMBlockBufferGetDataLength(blockBuffer!)
        let outOutputData:UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: 1)
        outOutputData[0].mNumberChannels = inDestinationFormat.mChannelsPerFrame
        outOutputData[0].mDataByteSize = UInt32(dataLength)
        outOutputData[0].mData = malloc(dataLength)

        let status:OSStatus = AudioConverterFillComplexBuffer(
            converter,
            inputDataProc,
            unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
            &ioOutputDataPacketSize,
            outOutputData.unsafeMutablePointer,
            nil
        )

        // XXX: perhaps mistake. but can support macOS BuiltIn Mic #61
        if (0 <= status && ioOutputDataPacketSize == 1) {
            var result:CMSampleBuffer?
            var timing:CMSampleTimingInfo = CMSampleTimingInfo()
            let numSamples:CMItemCount = sampleBuffer.numSamples
            CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription, sampleCount: numSamples, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result)
            CMSampleBufferSetDataBufferFromAudioBufferList(result!, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: outOutputData.unsafePointer)
            delegate?.sampleOutput(audio: result!)
        }

        for i in 0..<outOutputData.count {
            free(outOutputData[i].mData)
        }
        free(outOutputData.unsafeMutablePointer)
    }

    func invalidate() {
        lockQueue.async {
            self.inSourceFormat = nil
            self._inDestinationFormat = nil
            if let converter:AudioConverterRef = self._converter {
                AudioConverterDispose(converter)
            }
            self._converter = nil
        }
    }

    func onInputDataForAudioConverter(
        _ ioNumberDataPackets:UnsafeMutablePointer<UInt32>,
        ioData:UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription:UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {

        guard let bufferList:UnsafeMutableAudioBufferListPointer = currentBufferList else {
            ioNumberDataPackets.pointee = 0
            return -1
        }

        memcpy(ioData, bufferList.unsafePointer, bufferListSize)
        ioNumberDataPackets.pointee = 1
        free(bufferList.unsafeMutablePointer)
        currentBufferList = nil

        return noErr
    }
}

extension AACEncoder: AVCaptureAudioDataOutputSampleBufferDelegate {
    // MARK: AVCaptureAudioDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput:AVCaptureOutput!, didOutputSampleBuffer sampleBuffer:CMSampleBuffer!, from connection:AVCaptureConnection!) {
        encodeSampleBuffer(sampleBuffer)
    }
}
