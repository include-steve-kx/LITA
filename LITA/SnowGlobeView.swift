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

    // Memory state
    @State private var memoryImage: UIImage?
    @State private var memoryAsset: PHAsset?
    @State private var memoryPlaceName: String?
    @State private var showMemoryOverlay = false
    @State private var showMap = false

    var body: some View {
        ZStack {
            // 3D Scene
            SceneKitContainer(controller: sceneController)
                .ignoresSafeArea()

            // UI Overlay (only when 2D overlay is NOT showing)
            if !showMemoryOverlay {
                VStack {
                    // Top bar
                    topBar
                    Spacer()
                    loadingIndicators
                    hintText
                    bottomButton
                }
            }

            // 2D Memory overlay (appears after 3D animation finishes)
            if showMemoryOverlay, let image = memoryImage {
                MemoryOverlay(
                    image: image,
                    asset: memoryAsset,
                    placeName: memoryPlaceName,
                    onDismiss: dismissMemory,
                    onShowMap: { showMap = true }
                )
                .transition(.opacity)
                .zIndex(10)
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
        .onReceive(sceneController.$isShowingMemory) { showing in
            // When 3D animation finishes, show the 2D overlay on top
            if showing && memoryImage != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showMemoryOverlay = true
                }
            }
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

    // MARK: - Sub-views

    private var topBar: some View {
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
    }

    @ViewBuilder
    private var loadingIndicators: some View {
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
    }

    @ViewBuilder
    private var hintText: some View {
        if showHint && !photoManager.thumbnails.isEmpty && !sceneController.isShowingMemory {
            Text("Shake to stir up some memories")
                .font(.callout)
                .foregroundColor(.white.opacity(0.5))
                .transition(.opacity)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        if !photoManager.thumbnails.isEmpty && !sceneController.isShowingMemory {
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

    // MARK: - Random Memory Flow

    private func revealRandomMemory() {
        guard !isAnimating, !sceneController.isShowingMemory else { return }
        isAnimating = true
        withAnimation { showHint = false }

        photoManager.fetchRandomPhoto { image, asset in
            DispatchQueue.main.async {
                if let image {
                    self.memoryImage = image
                    self.memoryAsset = asset
                    self.sceneController.showMemory(image: image)
                    self.resolveLocation(for: asset)
                }
                self.isAnimating = false
            }
        }
    }

    private func dismissMemory() {
        // 1. Hide the 2D overlay instantly
        withAnimation(.easeInOut(duration: 0.25)) {
            showMemoryOverlay = false
        }
        // 2. Shrink the 3D plane away (after a tiny delay so the overlay fades first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sceneController.dismissMemory()
            memoryImage = nil
            memoryAsset = nil
            memoryPlaceName = nil
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

// MARK: - 2D Memory Overlay (zoomable photo with controls)

struct MemoryOverlay: View {
    let image: UIImage
    let asset: PHAsset?
    let placeName: String?
    let onDismiss: () -> Void
    let onShowMap: () -> Void

    @State private var appeared = false
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                Spacer()

                // Zoomable photo
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .white.opacity(0.06), radius: 30)
                    .padding(.horizontal, 20)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                zoom = max(1.0, min(5.0, value.magnification))
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if zoom < 1.2 {
                                        zoom = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if zoom > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .scaleEffect(appeared ? 1.0 : 0.95)
                    .opacity(appeared ? 1.0 : 0)

                Spacer()

                // Info + buttons at bottom
                VStack(spacing: 10) {
                    if let date = asset?.creationDate {
                        Text(date, style: .date)
                            .font(.callout.weight(.light))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    if let name = placeName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    HStack(spacing: 16) {
                        if asset?.location != nil {
                            Button(action: onShowMap) {
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

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.title3.bold())
                                .foregroundColor(.white.opacity(0.9))
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
                .opacity(appeared ? 1.0 : 0)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }
}
