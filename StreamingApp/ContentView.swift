//
//  ContentView.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

import SwiftUI

struct ContentView: View {
    let client = Client()
    var body: some View {
        ZStack{
            CameraPreview(cameraManager: CameraManager.shared)
                .cornerRadius(25)
            VStack{
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        client.connect(to: "172.20.10.13", with: 8080)
                        client.startStreaming()
                    }, label: {
                        Image(systemName: "video")
                            .foregroundColor(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(30)
                    })
                }
                .padding()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
