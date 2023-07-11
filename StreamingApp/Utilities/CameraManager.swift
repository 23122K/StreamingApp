//
//  CameraManager.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

import Foundation
import AVKit

public final class CameraManager {
    private enum CaptureSessionStatus {
        case sucess
        case failed
    }
    
    //MARK: - CameraManager properties
    private var videoDevices: Array<AVCaptureDevice.DeviceType> = [.builtInDualCamera, .builtInTripleCamera, .builtInWideAngleCamera]
    private var audioDevices: Array<AVCaptureDevice.DeviceType> = [.builtInMicrophone]
    
    private var captureDevicePosition: AVCaptureDevice.Position = .unspecified
    private var captureSessionStatus: CaptureSessionStatus = .sucess
    
    //MARK: - Dependencies
    public let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    
    private var videoInput: AVCaptureDeviceInput!
    private var audioInput: AVCaptureDeviceInput!
    
    //MARK: - Dispatch Queues
    private var captureSessionQueue = DispatchQueue(label: "capture.session")
    private var videoDataOutputQueue = DispatchQueue(label: "video.data.output")
    private var audioDataOutputQueue = DispatchQueue(label: "audio.data.output")
    
    private func configureCaptureSession() {
        captureSessionQueue.async { [self] in
            captureSession.beginConfiguration()
            
            requestAuthorization(for: .video)
            requestAuthorization(for: .audio)
        
            guard let videoDevice = availableVideoDevices?.first else { print("1"); return }
            guard let audioDevice = availableAudioDevices?.first else { print("2"); return }
            
            addVideoInputDeviceToCaptureSession(device: videoDevice)
            addAudioInputDeviceToCaptureSession(device: audioDevice)
            
            addOutputToCaptureSession(output: videoDataOutput)
            
            captureSession.sessionPreset = .hd1920x1080
            captureSession.commitConfiguration()
            
            startCaptureSession()
        }
    }
    
    private func requestAuthorization(for media: AVMediaType) {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized:
            return
        case .notDetermined:
            requestAccess(for: media)
        default:
            captureSessionStatus = .failed
        }
    }
    
    private func requestAccess(for media: AVMediaType) {
        captureSessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: media) { accessGranted in
            guard accessGranted else {
                self.captureSessionStatus = .failed
                return
            }
            
            self.captureSessionQueue.resume()
        }
    }
    
    //Returns available devices for position specified in property captureDevicePosition
    //might return nill if access for device has not been granted
    private var availableVideoDevices: Array<AVCaptureDevice>? {
        guard captureSessionStatus == .sucess else { return nil }
        return AVCaptureDevice.DiscoverySession(deviceTypes: videoDevices, mediaType: .video, position: captureDevicePosition).devices
    }
    
    private var availableAudioDevices: Array<AVCaptureDevice>? {
        guard captureSessionStatus == .sucess else { return nil }
        return AVCaptureDevice.DiscoverySession(deviceTypes: audioDevices, mediaType: .audio, position: captureDevicePosition).devices
    }
    
    
    private func addVideoInputDeviceToCaptureSession(device: AVCaptureDevice) {
        videoInput = try? AVCaptureDeviceInput(device: device)
        guard let videoInput = videoInput, captureSession.canAddInput(videoInput) else {
            captureSessionStatus = .failed
            return
        }
        
        captureSession.addInput(videoInput)
    }
    
    private func addAudioInputDeviceToCaptureSession(device: AVCaptureDevice) {
        audioInput = try? AVCaptureDeviceInput(device: device)
        guard let audioInput = audioInput, captureSession.canAddInput(audioInput) else {
            captureSessionStatus = .failed
            return
        }
        
        captureSession.addInput(audioInput)
    }
    
    private func addOutputToCaptureSession(output: AVCaptureOutput) {
        guard captureSession.canAddOutput(output) else {
            captureSessionStatus = .failed
            return
        }
        
        captureSession.addOutput(output)
    }
    
    private func removeCaptureDeviceInputFromCaptureSession(input device: AVCaptureDeviceInput) {
        captureSession.removeInput(device)
    }
    
    private func removeOutputFromCaptureSession(output: AVCaptureOutput) {
        captureSession.removeOutput(output)
    }
    
    private func startCaptureSession() {
        if !captureSession.isRunning { captureSession.startRunning() }
    }
    
    private func stopCaptureSession() {
        if captureSession.isRunning { captureSession.stopRunning() }
    }
    
    public static let shared = CameraManager()
    
    private init() {
        configureCaptureSession()
    }
    
    func setVideoDataOutputDelegate(with delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoDataOutput.setSampleBufferDelegate(delegate, queue: videoDataOutputQueue)
    }
    
    func setAudioDataOutputDelegate(with delegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        audioDataOutput.setSampleBufferDelegate(delegate, queue: audioDataOutputQueue)
    }
    
    
}
