//
//  AudioEncoder.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 12/07/2023.
//

import AVFoundation
import AudioToolbox

class AudioEncoder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //encode it
    }
    
    
}
