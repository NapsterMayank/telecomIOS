//
//  SystemVolumeBridge.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import AVFoundation
import MediaPlayer
import SwiftUI
import Combine

/// Bridges a SwiftUI-bound volume value to the real system output volume via
/// a hidden `MPVolumeView`.
///
/// MAP_PLATFORM_LIMITATION: iOS has no public `AVAudioSession` API to *set*
/// output volume directly — `MPVolumeView`'s embedded slider is the only
/// sanctioned way for an app to change system volume programmatically. This
/// view is laid out at effectively-zero opacity purely as that write path;
/// the visible slider in `LocalRecordingsView` keeps the screenshot look and
/// feel and drives this view's `volume` binding.
struct SystemVolumeBridge: UIViewRepresentable {
    @Binding var volume: Float
    
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first,
              abs(slider.value - volume) > 0.01 else { return }
        slider.setValue(volume, animated: false)
    }
}

/// Mirrors the live system output volume (e.g. from hardware volume buttons)
/// back into SwiftUI state via KVO on `AVAudioSession.outputVolume`.
@MainActor
final class SystemVolumeObserver: ObservableObject {
    @Published private(set) var volume: Double
    
    private var observation: NSKeyValueObservation?
    
    init() {
        let session = AVAudioSession.sharedInstance()
        volume = Double(session.outputVolume)
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let newVolume = Double(session.outputVolume)
            Task { @MainActor in
                self?.volume = newVolume
            }
        }
    }
}
