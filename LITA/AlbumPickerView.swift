//
//  AlbumPickerView.swift
//  LITA
//

import SwiftUI

struct AlbumPickerView: View {
    @ObservedObject var photoManager: PhotoManager
    @Binding var selectedAlbum: AlbumInfo?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "snowflake")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .padding(.top, 60)

                Text("LITA")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundColor(.white)

                Text("Choose an album to fill the snow globe")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 24)
            }

            // Content
            if photoManager.permissionDenied {
                permissionDeniedView
            } else if photoManager.albums.isEmpty {
                loadingView
            } else {
                albumListView
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.03, blue: 0.12),
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            if !photoManager.permissionGranted && !photoManager.permissionDenied {
                photoManager.requestPermission()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading albums...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, 60)
        .frame(maxHeight: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange.opacity(0.7))
            Text("Photo access is required")
                .font(.headline)
                .foregroundColor(.white)
            Text("Please enable photo access in Settings\nto fill the snow globe with memories.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxHeight: .infinity)
    }

    private var albumListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(photoManager.albums) { album in
                    Button(action: { selectedAlbum = album }) {
                        HStack(spacing: 14) {
                            Image(systemName: albumIcon(for: album))
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(album.title)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(album.count) photos")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.2))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.04))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    private func albumIcon(for album: AlbumInfo) -> String {
        let title = album.title.lowercased()
        if title.contains("favorite") { return "heart.fill" }
        if title.contains("recent") { return "clock.fill" }
        if title.contains("selfie") { return "person.crop.circle" }
        if title.contains("panorama") { return "pano.fill" }
        if title.contains("video") { return "video.fill" }
        if title.contains("screenshot") { return "camera.viewfinder" }
        return "photo.on.rectangle.angled"
    }
}
