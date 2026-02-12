//
//  SnowGlobeView.swift
//  LITA
//

import CoreLocation
import Photos
import SceneKit
import SwiftUI

// MARK: - SceneKit UIViewRepresentable

struct SceneKitContainer: UIViewRepresentable {
    let controller: SnowGlobeSceneController

    func makeUIView(context: Context) -> ShakableSCNView {
        return controller.scnView
    }

    func updateUIView(_ uiView: ShakableSCNView, context: Context) {}
}

// MARK: - Snow Globe View

struct SnowGlobeView: View {
    @ObservedObject var photoManager: PhotoManager
    let album: AlbumInfo
    let onBack: () -> Void

    @StateObject private var sceneController = SnowGlobeSceneController()
    @State private var isAnimating = false
    @State private var showHint = true
    @State private var showDebug = false

    // Memory location state
    @State private var memoryAsset: PHAsset?
    @State private var memoryPlaceName: String?
    @State private var showMap = false

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

                    Button(action: { showDebug = true }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Loading thumbnails
                if photoManager.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: photoManager.loadingProgress)
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                            .frame(width: 180)
                        Text("Loading memories… \(Int(photoManager.loadingProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 12)
                    Spacer()
                }

                // Downloading hi-res memory from iCloud
                if photoManager.isFetchingMemory {
                    VStack(spacing: 6) {
                        ProgressView(value: photoManager.memoryDownloadProgress)
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                            .frame(width: 160)
                        Text("Fetching photo…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                // Hint
                if showHint && !photoManager.thumbnails.isEmpty && !sceneController.isShowingMemory {
                    Text("Shake to stir up some memories")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.5))
                        .transition(.opacity)
                        .padding(.bottom, 8)
                }

                // Bottom controls
                if !photoManager.thumbnails.isEmpty {
                    if sceneController.isShowingMemory {
                        // Memory info + controls
                        VStack(spacing: 10) {
                            // Date
                            if let date = memoryAsset?.creationDate {
                                Text(date, style: .date)
                                    .font(.callout.weight(.light))
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            // Place name
                            if let name = memoryPlaceName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            HStack(spacing: 16) {
                                // "See where this was" button
                                if memoryAsset?.location != nil {
                                    Button(action: { showMap = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "globe.americas.fill")
                                            Text("See where")
                                        }
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial, in: Capsule())
                                    }
                                }

                                // Dismiss
                                Button(action: {
                                    sceneController.dismissMemory()
                                    memoryAsset = nil
                                    memoryPlaceName = nil
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title3.bold())
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(12)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                            }
                        }
                        .padding(.bottom, 50)
                        .transition(.opacity)
                    } else {
                        // Show Memory button
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
                        .transition(.opacity)
                    }
                }
            }
        }
        .onAppear {
            photoManager.loadThumbnails(from: album)
            sceneController.startDeviceMotion()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation { showHint = false }
            }
        }
        .onDisappear {
            sceneController.stopDeviceMotion()
        }
        .onReceive(photoManager.$thumbnails) { thumbnails in
            sceneController.updateThumbnails(thumbnails)
        }
        .sheet(isPresented: $showDebug) {
            DebugOverlayView(controller: sceneController)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMap) {
            if let location = memoryAsset?.location {
                GlobeMapView(location: location, placeName: memoryPlaceName)
            }
        }
    }

    // MARK: - Random Memory Flow

    private func revealRandomMemory() {
        guard !isAnimating, !sceneController.isShowingMemory else { return }
        isAnimating = true
        withAnimation { showHint = false }

        photoManager.fetchRandomPhoto { image, asset in
            DispatchQueue.main.async {
                if let image {
                    self.memoryAsset = asset
                    self.sceneController.showMemory(image: image)
                    self.resolveLocation(for: asset)
                }
                self.isAnimating = false
            }
        }
    }

    private func resolveLocation(for asset: PHAsset?) {
        guard let location = asset?.location else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let pm = placemarks?.first {
                let parts = [pm.locality, pm.administrativeArea, pm.country]
                    .compactMap { $0 }
                DispatchQueue.main.async {
                    self.memoryPlaceName = parts.joined(separator: ", ")
                }
            }
        }
    }
}
