//
//  GlobeMapView.swift
//  LITA
//

import CoreLocation
import MapKit
import SwiftUI

struct GlobeMapView: View {
    let location: CLLocation
    let placeName: String?

    @State private var cameraPosition: MapCameraPosition
    @Environment(\.dismiss) private var dismiss

    init(location: CLLocation, placeName: String?) {
        self.location = location
        self.placeName = placeName
        // Start zoomed out so the user sees the full globe
        _cameraPosition = State(
            initialValue: .camera(
                MapCamera(
                    centerCoordinate: location.coordinate,
                    distance: 20_000_000, // ~20,000 km -> full Earth
                    heading: 0,
                    pitch: 0
                )
            )
        )
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                Marker(placeName ?? "Memory", coordinate: location.coordinate)
                    .tint(.pink)
            }
            .mapStyle(.imagery(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear {
                // Delay briefly so the globe renders first, then zoom in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 3.0)) {
                        cameraPosition = .camera(
                            MapCamera(
                                centerCoordinate: location.coordinate,
                                distance: 50_000, // ~50 km
                                heading: 0,
                                pitch: 45
                            )
                        )
                    }
                }
            }

            // Overlay UI
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    Spacer()
                }

                Spacer()

                if let name = placeName {
                    Text(name)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 8, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 50)
                }
            }
        }
    }
}
