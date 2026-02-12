//
//  ContentView.swift
//  LITA
//
//  Created by Steve KX on 2/11/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var photoManager = PhotoManager()
    @State private var selectedAlbum: AlbumInfo?

    var body: some View {
        Group {
            if let album = selectedAlbum {
                SnowGlobeView(
                    photoManager: photoManager,
                    album: album,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAlbum = nil
                        }
                    }
                )
                .transition(.opacity)
            } else {
                AlbumPickerView(
                    photoManager: photoManager,
                    selectedAlbum: $selectedAlbum
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedAlbum)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
