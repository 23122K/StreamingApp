//
//  ContentView.swift
//  StreamingApp
//
//  Created by Patryk Maciąg on 10/07/2023.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack{
            CameraPreview(cameraManager: CameraManager.shared)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
