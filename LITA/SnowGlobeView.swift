//
//  SnowGlobeView.swift
//  LITA
//

import Photos
import SceneKit
import SwiftUI

// MARK: - SceneKit UIViewRepresentable

struct SceneKitContainer: UIViewRepresentable {
    let controller: SnowGlobeSceneController

    func makeUIView(context: Context) -> ShakableSCNView {
        return controller.scnView
    }

    func updateUIView(_ uiView: ShakableSCNView, context: Context) {
        // Updates are handled imperatively through the controller
    }
}

// MARK: - Snow Globe View

struct SnowGlobeView: View {
    @ObservedObject var photoManager: PhotoManager
    let album: AlbumInfo
    let onBack: () -> Void

    @StateObject private var sceneController = SnowGlobeSceneController()
    @State private var showingMemory = false
    @State private var memoryImage: UIImage?
    @State private var memoryAsset: PHAsset?
    @State private var isAnimating = false
    @State private var showHint = true

    var body: some View {
        ZStack {
            // 3D Scene
            SceneKitContainer(controller: sceneController)
                .ignoresSafeArea()

            // UI Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2.bold())
                            .foregroundColor(.white.opacity(0.8))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Loading indicator
                if photoManager.isLoading && photoManager.thumbnails.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading memories...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }

                // Hint text
                if showHint && !photoManager.thumbnails.isEmpty {
                    Text("Shake to stir up some memories")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.5))
                        .transition(.opacity)
                        .padding(.bottom, 8)
                }

                // Random Memory button
                if !photoManager.thumbnails.isEmpty {
                    Button(action: revealRandomMemory) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Show me a memory")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(isAnimating)
                    .opacity(isAnimating ? 0.5 : 1.0)
                    .padding(.bottom, 50)
                }
            }

            // Memory Detail Overlay
            if showingMemory, let image = memoryImage {
                MemoryDetailView(
                    image: image,
                    asset: memoryAsset,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showingMemory = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(1)
            }
        }
        .onAppear {
            photoManager.loadThumbnails(from: album)
            // Hide hint after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation { showHint = false }
            }
        }
        .onReceive(photoManager.$thumbnails) { thumbnails in
            sceneController.updateThumbnails(thumbnails)
        }
    }

    // MARK: - Random Memory Flow

    private func revealRandomMemory() {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation { showHint = false }

        let group = DispatchGroup()

        // Fetch a random full-resolution photo from the entire album
        group.enter()
        photoManager.fetchRandomPhoto { image, asset in
            self.memoryImage = image
            self.memoryAsset = asset
            group.leave()
        }

        // Animate a snowflake flying out of the globe
        group.enter()
        sceneController.flyOutAnimation {
            group.leave()
        }

        // Show memory when both are ready
        group.notify(queue: .main) {
            if self.memoryImage != nil {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.showingMemory = true
                }
            }
            self.isAnimating = false
        }
    }
}
