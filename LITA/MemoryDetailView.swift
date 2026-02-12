//
//  MemoryDetailView.swift
//  LITA
//

import CoreLocation
import Photos
import SwiftUI

struct MemoryDetailView: View {
    let image: UIImage
    let asset: PHAsset?
    let onDismiss: () -> Void

    @State private var showMap = false
    @State private var placeName: String?
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Blurred dark background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                // Dismiss button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // Photo
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .white.opacity(0.08), radius: 30)
                    .padding(.horizontal, 24)
                    .scaleEffect(appeared ? 1.0 : 0.85)
                    .opacity(appeared ? 1.0 : 0)

                // Date
                if let date = asset?.creationDate {
                    Text(date, style: .date)
                        .font(.title3.weight(.light))
                        .foregroundColor(.white.opacity(0.8))
                        .opacity(appeared ? 1.0 : 0)
                }

                // Location name
                if let name = placeName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .opacity(appeared ? 1.0 : 0)
                }

                // "See where this was" button
                if asset?.location != nil {
                    Button(action: { showMap = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe.americas.fill")
                            Text("See where this was")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .opacity(appeared ? 1.0 : 0)
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            resolveLocation()
        }
        .sheet(isPresented: $showMap) {
            if let location = asset?.location {
                GlobeMapView(location: location, placeName: placeName)
            }
        }
    }

    // MARK: - Reverse Geocode

    private func resolveLocation() {
        guard let location = asset?.location else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let pm = placemarks?.first {
                let parts = [pm.locality, pm.administrativeArea, pm.country]
                    .compactMap { $0 }
                DispatchQueue.main.async {
                    self.placeName = parts.joined(separator: ", ")
                }
            }
        }
    }
}
