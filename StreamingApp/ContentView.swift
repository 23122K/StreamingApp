//
//  ContentView.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

import SwiftUI

struct ContentView: View {
    
    //For testing purposes only
    let videoEncoder = VideoEncoder()
    let tcpClient = TCPClient()
    
    func connect(to ipAddress: String, with port: UInt16) {
        tcpClient.connect(to: ipAddress, with: port)
    }
    
    func startStreaming() {
        print(#function)
        videoEncoder.configureCompressionSession()
        CameraManager.shared.setVideoDataOutputDelegate(with: videoEncoder)
        videoEncoder.naluHandler = { data in
            self.tcpClient.send(data: data)
        }
    }
    
    var body: some View {
        ZStack{
            CameraPreview(cameraManager: CameraManager.shared)
            VStack{
                Button(action: {
                    startStreaming()
                }, label: {
                    Text("Start")
                        .foregroundColor(.white)
                        .font(.title)
                        .fontWeight(.semibold)
                })
            }
        }
        .onAppear{
            connect(to: "172.20.10.13", with: 8080)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
