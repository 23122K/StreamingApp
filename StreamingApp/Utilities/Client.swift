//
//  Client.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 14/07/2023.
//

import Foundation

class Client: VideoEncoderOutputDelegate {
    func encodedDataOuput(_ encodedData: Data) {
        tcpClient.send(data: encodedData)
    }
    
    let videoEncoder = VideoEncoder()
    let tcpClient = TCPClient()
    
    
    func connect(to ipAddress: String, with port: UInt16) {
        tcpClient.connect(to: ipAddress, with: port)
    }
    
    func startStreaming() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { [self] in
            videoEncoder.configureCompressionSession()
            CameraManager.shared.setVideoDataOutputDelegate(with: videoEncoder)
            videoEncoder.encodedDataDelegate = self
        })
    }
}
