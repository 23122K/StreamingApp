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
            VStack{
                Spacer()
                Button(action: {
                    client.startStreaming()
                }, label: {
                    Text("Start")
                        .foregroundColor(.white)
                        .font(.title)
                        .fontWeight(.semibold)
                })
            }
        }
        .onAppear{
            client.connect(to: "172.20.10.13", with: 8080)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
