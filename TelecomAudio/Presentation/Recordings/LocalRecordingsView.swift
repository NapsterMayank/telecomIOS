//
//  LocalRecordingsView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI

/// Participant live meeting screen — matches Android reference screenshots:
/// status icons inside the white card, volume slider, Leave/Speaker/
/// Recordings, and the large mic (tap or press-and-hold based on settings).
/// Pause/Resume lives in Settings and auto-pauses on background/calls.
@available(iOS 17.0, *)
struct LocalRecordingsView: View {
    @StateObject var viewModel: LocalRecordingsViewModel
    @StateObject private var systemVolume = SystemVolumeObserver()
    @State private var volumeBridgeValue: Float = 0.7
    @State private var pulse = false
    @State private var isRecordingOptionsExpanded = false

    var body: some View {
        ZStack {
            if viewModel.showWaitingScreen {
                waitingForHostView
            } else {
                ZStack {
                    meetingContent
                    if viewModel.showSettings {
                        settingsOverlay
                    }
                    if viewModel.showRecordings {
                        recordingsSheet
                            .zIndex(80)
                    }
                    if viewModel.showMeetingRecordingNotice {
                        MeetingRecordingNoticeDialog(
                            onAcknowledge: { viewModel.dismissMeetingRecordingNotice() }
                        )
                        .zIndex(90)
                    }
                }
            }

            if viewModel.showLeaveConfirmation {
                LeaveMeetingDialog(
                    onCancel: { viewModel.cancelLeave() },
                    onConfirm: { viewModel.confirmLeave() }
                )
                .zIndex(120)
            }

            if viewModel.isDisconnecting {
                ZoomMeetingStatusScreen(
                    kind: .disconnecting,
                    title: "Disconnecting from meeting...",
                    subtitle: "Cleaning up session states..."
                )
                .zIndex(200)
                .transition(.opacity)
            }
        }
        .background(AppColors.meetingBackground.ignoresSafeArea())
        .background(SystemVolumeBridge(volume: $volumeBridgeValue).frame(width: 0, height: 0))
        .onDisappear {
            viewModel.endPushToTalk()
            viewModel.stopLifecycleObservers()
        }
        .onAppear {
            viewModel.onScreenAppear()
            viewModel.startLifecycleObservers()
            viewModel.setVolume(systemVolume.volume)
            volumeBridgeValue = Float(viewModel.volume)
            pulse = true
        }
        .onChange(of: systemVolume.volume) { _, newValue in
            if abs(viewModel.volume - newValue) > 0.01 {
                viewModel.setVolume(newValue)
            }
        }
        .onChange(of: viewModel.volume) { _, newValue in
            volumeBridgeValue = Float(newValue)
        }
        // Keep animations local to controls — do NOT animate `showSettings` on
        // the whole screen (that causes a white/content blink on Close).
        // Do NOT animate isPaused / listen-banner here — that made the
        // Listening On/Off strip blink whenever pause toggled.
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPushToTalkActive)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isEarphoneMode)
        .animation(.easeInOut(duration: 0.2), value: viewModel.hostStatusMessage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showLeaveConfirmation)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showMeetingRecordingNotice)
    }

    // MARK: - Main meeting layout

    private var meetingContent: some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 700
            let sessionCardMaxHeight = sessionCardScrollHeight(in: geometry)

            VStack(spacing: 0) {
                if viewModel.showListeningOnByHost {
                    listeningOnByHostBanner
                        // Block any inherited animation so the strip doesn't fade/blink.
                        .transaction { $0.animation = nil }
                }
                if !viewModel.hostStatusMessage.isEmpty {
                    HostStatusBanner(
                        message: viewModel.hostStatusMessage,
                        showsDismissButton: false
                    )
                }

                Group {
                    if isCompactHeight {
                        ScrollView(showsIndicators: false) {
                            sessionCardSection(screenWidth: geometry.size.width)
                        }
                        .frame(maxHeight: sessionCardMaxHeight)
                    } else {
                        sessionCardSection(screenWidth: geometry.size.width)
                    }
                }

                volumeRow
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                actionButtonsRow
                    .padding(.top, 12)

                // Remaining height: mic centered with equal top/bottom gap (Android).
                bigMicToggle
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    // MARK: - Waiting for host

    private var waitingForHostView: some View {
        ZStack {
            AppColors.navy.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)

                VStack(spacing: 8) {
                    Text("Waiting for Host...")
                        .font(AppFonts.headline(20))
                        .foregroundStyle(.white)
                    Text("Host has not joined yet.")
                        .font(AppFonts.body(14))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Please wait...")
                        .font(AppFonts.body(14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    viewModel.requestLeave()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.down.fill")
                        Text("Leave Meeting")
                            .font(AppFonts.button(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.endRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Listening On / Off by Host

    private var listeningOnByHostBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.listeningByHostIsOff
                      ? "speaker.slash.fill"
                      : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(viewModel.listeningByHostIsOff
                   ? "Listening Off by Host"
                   : "Listening On by Host")
                    .font(AppFonts.bodyBold(14))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    viewModel.dismissListeningOnByHost()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            listeningBannerCountdownBar
                .frame(height: 3)
        }
        .background(AppColors.navy.ignoresSafeArea(edges: .top))
    }

    /// Date-based drain — avoids @Published step/animation flicker on the bar.
    private var listeningBannerCountdownBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let remaining: CGFloat = {
                guard let endsAt = viewModel.listeningBannerEndsAt else { return 0 }
                let secondsLeft = endsAt.timeIntervalSince(context.date)
                return CGFloat(min(1, max(0, secondsLeft / 5.0)))
            }()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * remaining))
                }
            }
        }
    }

    // MARK: - Session card

    private func sessionAvatarSize(for screenWidth: CGFloat) -> CGFloat {
        let cardContentWidth = screenWidth - 32 - 36
        return min(max(cardContentWidth * 0.55, 132), 188)
    }

    private func sessionCardSection(screenWidth: CGFloat) -> some View {
        sessionCard(avatarSize: sessionAvatarSize(for: screenWidth))
            .padding(.horizontal, 16)
            .padding(.top, viewModel.showListeningOnByHost ? 12 : 8)
    }

    private func sessionCardScrollHeight(in geometry: GeometryProxy) -> CGFloat {
        let reservedBottom: CGFloat = 14 + 36 + 12 + 70 + 240
        let reservedTop: CGFloat = (viewModel.showListeningOnByHost ? 52 : 8)
            + (!viewModel.hostStatusMessage.isEmpty ? 48 : 0)
            + 16
        return max(300, geometry.size.height - reservedBottom - reservedTop)
    }

    private func sessionCard(avatarSize: CGFloat) -> some View {
        VStack(spacing: 14) {
            statusIconsRow

            HStack {
                Spacer(minLength: 0)
                hostOrOwnerBadge
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) {
                Button {
                    viewModel.openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.35, green: 0.35, blue: 0.38))
                }
            }

            SessionAvatarView(
                profileImage: viewModel.sessionProfileImage,
                zoomAvatarFileURL: viewModel.hostAvatarURL,
                size: avatarSize
            )
                .padding(.top, 6)

            VStack(spacing: 4) {
                Text(viewModel.banner ?? "")
                    .font(AppFonts.body(16))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

//                if !viewModel.sessionTitle.isEmpty {
//                    Text(viewModel.sessionTitle)
//                        .font(AppFonts.headline(22))
//                        .foregroundStyle(AppColors.textPrimary)
//                        .multilineTextAlignment(.center)
//                }
//                Text(viewModel.sessionUsername)
//                    .font(AppFonts.body(14))
//                    .foregroundStyle(AppColors.textSecondary)
//                    .multilineTextAlignment(.center)
            }

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Android: book owner name pill, or name + host network when Host Network Indicator is on.
    @ViewBuilder
    private var hostOrOwnerBadge: some View {
        if viewModel.settings.hostNetworkIndicator {
            HStack(spacing: 8) {
                Text(viewModel.sessionOwnerName)
                    .font(AppFonts.bodyBold(14))
                    .foregroundStyle(AppColors.black)
                NetworkSignalView(
                    quality: viewModel.hostNetworkQuality,
                    onLightBackground: true
                )
                .scaleEffect(0.9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(AppColors.namePillLavender)
            .clipShape(Capsule())
        } else {
            Text(viewModel.sessionOwnerName)
                .font(AppFonts.bodyBold(14))
                .foregroundStyle(AppColors.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppColors.namePillLavender)
                .clipShape(Capsule())
        }
    }

    /// Android card status row: participant network / call / speaker / mic.
    private var statusIconsRow: some View {
        HStack(spacing: 14) {
            if viewModel.showRecordingStatusPill {
                Image("rec-button")
                    .resizable()
                    .frame(width: 20, height: 20)
                   // .foregroundStyle(AppColors.muteRed)
                    .allowsHitTesting(false)
//                Circle()
//                    .fill(AppColors.muteRed)
//                    .frame(width: 10, height: 10)
//                    .shadow(
//                        color: viewModel.isMicRecordingPillActive ? AppColors.muteRed.opacity(0.8) : .clear,
//                        radius: 4
//                    )
                    .accessibilityLabel(viewModel.recordingStatusText)
            }
            // Participant's own live network (not the host's).
            NetworkSignalView(
                quality: viewModel.networkQuality,
                onLightBackground: true
            )

            Image(systemName: viewModel.isPaused ? "pause.circle.fill" : "phone.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.isPaused ? AppColors.muteRed : AppColors.speakerGreen)

            Image(systemName: viewModel.speakerButtonIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.speakerGreen)

            Image(systemName: viewModel.isPushToTalkActive ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.isPushToTalkActive ? AppColors.speakerGreen : AppColors.muteRed)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Volume (Android thick black track)

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            ThickVolumeSlider(value: Binding(
                get: { viewModel.volume },
                set: { viewModel.setVolume($0) }
            ))
            .frame(height: 28)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Action buttons

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            controlButton(title: "Leave", icon: "power", color: AppColors.endRed) {
                viewModel.requestLeave()
            }
            controlButton(
                title: viewModel.speakerButtonTitle,
                icon: viewModel.speakerButtonIcon,
                color: AppColors.controlSlate,
                isDisabled: viewModel.isPaused
            ) {
                viewModel.toggleSpeakerEarphone()
            }
            controlButton(title: "Recordings", icon: "music.note.list", color: AppColors.controlSlate) {
                viewModel.openRecordings()
            }
        }
        .padding(.horizontal, 16)
    }

    private func controlButton(
        title: String,
        icon: String,
        color: Color,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(AppFonts.button(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(isDisabled ? color.opacity(0.4) : color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isDisabled)
    }

    // MARK: - Big mic

    private var bigMicToggle: some View {
        GeometryReader { geo in
            // Android: large circle centered in leftover area with balanced
            // padding above (under action row) and below (above home bar).
            let maxSide = min(geo.size.width, geo.size.height) - 36
            let side = min(max(160, maxSide * 0.82), 260)
            let content = bigMicContent(diameter: side)

            Group {
                if viewModel.isPaused {
                    Button {
                        viewModel.tapBigMicWhilePaused()
                    } label: {
                        content
                    }
                } else if viewModel.settings.unmuteWithTouch {
                    Button {
                        viewModel.tapMicForTouchUnmute()
                    } label: {
                        content
                    }
                } else {
                    content
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    viewModel.beginPushToTalk()
                                }
                                .onEnded { _ in
                                    viewModel.endPushToTalk()
                                }
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: viewModel.isPushToTalkActive) { _, active in
            if active {
                pulse = false
                DispatchQueue.main.async {
                    pulse = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showResumeToSpeakHint)
    }

    private func bigMicContent(diameter: CGFloat) -> some View {
        let ring = diameter + 22
        let ripple = diameter + 4
        let iconSize = diameter * (viewModel.isPaused ? 0.42 : (viewModel.isPushToTalkActive ? 0.46 : 0.44))

        return ZStack {
            if viewModel.isPushToTalkActive {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .stroke(
                            AppColors.micGlowGreen.opacity(micRippleStrokeOpacity(index)),
                            lineWidth: 3
                        )
                        .frame(width: ripple, height: ripple)
                        .scaleEffect(pulse ? micRippleZoomScale(index) : 1.0)
                        .opacity(pulse ? 0.15 : micRippleFillOpacity(index) + 0.25)
                        .animation(
                            .easeOut(duration: 1.35)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.22),
                            value: pulse
                        )

                    Circle()
                        .fill(AppColors.micGlowGreen.opacity(micRippleFillOpacity(index)))
                        .frame(width: ripple, height: ripple)
                        .scaleEffect(pulse ? micRippleZoomScale(index) : 1.0)
                        .opacity(pulse ? 0.05 : micRippleFillOpacity(index))
                        .animation(
                            .easeOut(duration: 1.35)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.22),
                            value: pulse
                        )
                }
            } else if !viewModel.isPaused {
                Circle()
                    .stroke(Color.gray.opacity(0.28), lineWidth: max(12, diameter * 0.07))
                    .frame(width: ring, height: ring)
            }

            Circle()
                .fill(bigMicFillColor)
                .frame(width: diameter, height: diameter)
                .scaleEffect(viewModel.isPushToTalkActive ? (pulse ? 1.08 : 0.96) : 1.0)
                .shadow(
                    color: viewModel.isPushToTalkActive
                        ? AppColors.micGlowGreen.opacity(0.45)
                        : (viewModel.isPaused ? AppColors.muteRed.opacity(0.35) : .clear),
                    radius: viewModel.isPaused ? 10 : 18,
                    y: 4
                )
                .animation(
                    viewModel.isPushToTalkActive
                        ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                    value: pulse
                )

            Image(systemName: bigMicIconName)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(viewModel.isPushToTalkActive ? (pulse ? 1.1 : 0.95) : 1.0)
                .animation(
                    viewModel.isPushToTalkActive
                        ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                    value: pulse
                )

            if viewModel.showResumeToSpeakHint {
                resumeMeetingToSpeakPill
                    .offset(y: diameter * 0.28)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    /// Android toast over red X: mic icon + "Resume meeting to speak".
    private var resumeMeetingToSpeakPill: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(red: 45 / 255, green: 45 / 255, blue: 48 / 255))
                    .frame(width: 28, height: 28)
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Resume meeting to speak")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 55 / 255, green: 55 / 255, blue: 58 / 255))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 245 / 255, green: 232 / 255, blue: 216 / 255))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
    }

    private func micRippleZoomScale(_ index: Int) -> CGFloat {
        1.35 + CGFloat(index) * 0.28
    }

    private func micRippleFillOpacity(_ index: Int) -> Double {
        switch index {
        case 0: return 0.32
        case 1: return 0.22
        case 2: return 0.14
        default: return 0.08
        }
    }

    private func micRippleStrokeOpacity(_ index: Int) -> Double {
        switch index {
        case 0: return 0.55
        case 1: return 0.38
        case 2: return 0.24
        default: return 0.14
        }
    }

    private var bigMicFillColor: Color {
        if viewModel.isPaused { return AppColors.muteRed }
        if viewModel.isPushToTalkActive { return AppColors.micGlowGreen }
        return AppColors.participantMicGray
    }

    private var bigMicIconName: String {
        if viewModel.isPaused { return "xmark" }
        if viewModel.isPushToTalkActive { return "mic.fill" }
        return "mic.slash.fill"
    }

    // MARK: - Settings overlay (Android modal)

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { viewModel.closeSettings() }

            VStack(spacing: 0) {
                Text("Settings")
                    .font(AppFonts.headline(22))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Divider()
                    .overlay(AppColors.border)

                VStack(spacing: 22) {
                    settingsToggleRow(
                        title: viewModel.showsResumeButton ? "Resume Meeting" : "Pause Meeting",
                        subtitle: viewModel.showsResumeButton
                            ? "Resume listening to the host"
                            : "Pause listening; also auto-pauses in background or on calls",
                        isOn: Binding(
                            get: { viewModel.isPaused },
                            set: { viewModel.setPaused($0) }
                        )
                    )
                    // Unmute with Indicator — hidden for now
                    // settingsToggleRow(
                    //     title: "Unmute with Indicator",
                    //     subtitle: "Unmute with success indicator",
                    //     isOn: Binding(
                    //         get: { viewModel.settings.unmuteWithIndicator },
                    //         set: { viewModel.settings.unmuteWithIndicator = $0 }
                    //     )
                    // )
                    settingsToggleRow(
                        title: "Unmute with Touch",
                        subtitle: "Unmute with touch button",
                        isOn: Binding(
                            get: { viewModel.settings.unmuteWithTouch },
                            set: { viewModel.settings.unmuteWithTouch = $0 }
                        )
                    )
                    settingsToggleRow(
                        title: "Host Network Indicator",
                        subtitle: "Show host network strength",
                        isOn: Binding(
                            get: { viewModel.settings.hostNetworkIndicator },
                            set: { viewModel.settings.hostNetworkIndicator = $0 }
                        )
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recording System")
                            .font(AppFonts.bodyBold(15))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Try recording from this system")
                            .font(AppFonts.caption(13))
                            .foregroundStyle(AppColors.textSecondary)

                        // Custom dropdown — SwiftUI `Menu` inside a ZStack overlay
                        // often ignores taps; expand-in-place works reliably.
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRecordingOptionsExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text(viewModel.settings.recordingSystem)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .rotationEffect(.degrees(isRecordingOptionsExpanded ? 180 : 0))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppColors.fieldBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(AppColors.fieldBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if isRecordingOptionsExpanded {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(LocalMeetingSettingsStore.recordingSystemOptions, id: \.self) { option in
                                        Button {
                                            viewModel.selectRecordingSystem(option)
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                isRecordingOptionsExpanded = false
                                            }
                                        } label: {
                                            HStack {
                                                Text(option)
                                                    .font(AppFonts.body(15))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                Spacer()
                                                if option == viewModel.settings.recordingSystem {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(AppColors.speakerGreen)
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        if option != LocalMeetingSettingsStore.recordingSystemOptions.last {
                                            Divider()
                                                .overlay(AppColors.border)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 180)
                            .background(AppColors.fieldBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)

                Button {
                    viewModel.closeSettings()
                } label: {
                    Text("Close")
                        .font(AppFonts.button(16))
                        .foregroundStyle(AppColors.cardBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppColors.textPrimary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 28)
            // Keep taps on the card from dismissing via the dimmed backdrop.
            .contentShape(Rectangle())
        }
        .onChange(of: viewModel.showSettings) { _, isShown in
            if !isShown { isRecordingOptionsExpanded = false }
        }
    }

    private func settingsToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyBold(15))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.caption(13))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppColors.speakerGreen)
        }
    }

    // MARK: - Recordings sheet

    private var recordingsSheet: some View {
        LocalRecordingsPanel(
            isEmpty: viewModel.recordings.isEmpty,
            emptyMessage: "Recordings you capture during this session will appear here.",
            canDeleteAll: !viewModel.recordings.isEmpty,
            groupedRecordings: viewModel.groupedRecordings,
            playback: viewModel.recordingPlayback,
            isPlaybackActive: viewModel.isPlaybackActive,
            isPlaybackPlaying: viewModel.isPlaybackPlaying,
            onTogglePlayback: viewModel.togglePlayback,
            onDelete: viewModel.requestDelete,
            onDeleteAll: viewModel.requestDeleteAll,
            onClose: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.showRecordings = false
                }
            },
            pendingDeletion: viewModel.recordingPendingDeletion,
            showDeleteAllConfirmation: viewModel.showDeleteAllConfirmation,
            onCancelDelete: viewModel.cancelDelete,
            onConfirmDelete: viewModel.confirmDelete,
            onCancelDeleteAll: viewModel.cancelDeleteAll,
            onConfirmDeleteAll: viewModel.confirmDeleteAll
        )
        .transaction { $0.animation = nil }
    }
}

/// Participant Leave Meeting confirm — Android light + dark (exit icon, No / Yes).
private struct LeaveMeetingDialog: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    private var confirmColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    private var cancelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : AppColors.black
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(iconColor)
                    .padding(.top, 4)

                Text("Leave Meeting")
                    .font(AppFonts.headline(20))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Are you sure you want to leave the meeting?")
                    .font(AppFonts.body(15))
                    .foregroundStyle(AppColors.textPrimary.opacity(colorScheme == .dark ? 0.85 : 0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                HStack(spacing: 70) {
                    Button("No", action: onCancel)
                        .font(AppFonts.button(16))
                        .foregroundStyle(cancelColor)

                    Button("Yes", action: onConfirm)
                        .font(AppFonts.button(16))
                        .fontWeight(.bold)
                        .foregroundStyle(confirmColor)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(maxWidth: 340)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.45 : 0.22),
                radius: 20,
                y: 8
            )
            .padding(.horizontal, 36)
        }
        .transition(.opacity)
    }
}

/// Android-style volume control: thick track + circular thumb (adapts to dark mode).
private struct ThickVolumeSlider: View {
    @Binding var value: Double
    @Environment(\.colorScheme) private var colorScheme

    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 26

    private var activeTrackColor: Color {
        colorScheme == .dark
            ? Color(red: 82 / 255, green: 195 / 255, blue: 240 / 255)
            : Color.black
    }

    private var inactiveTrackColor: Color {
        colorScheme == .dark
            ? Color(red: 30 / 255, green: 70 / 255, blue: 90 / 255)
            : Color.gray.opacity(0.45)
    }

    private var thumbColor: Color {
        colorScheme == .dark
            ? Color(red: 82 / 255, green: 195 / 255, blue: 240 / 255)
            : Color.black
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clampedValue = min(max(value, 0), 1)

            // Keep the thumb fully inside the slider
            let usableWidth = max(width - thumbSize, 1)
            let thumbOffset = CGFloat(clampedValue) * usableWidth

            ZStack(alignment: .leading) {

                // Inactive track
                Capsule()
                    .fill(inactiveTrackColor)
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                // Active track
                Capsule()
                    .fill(activeTrackColor)
                    .frame(
                        width: max(
                            trackHeight,
                            thumbOffset + thumbSize / 2
                        ),
                        height: trackHeight
                    )

                // Thumb
                Circle()
                    .fill(thumbColor)
                    .frame(
                        width: thumbSize,
                        height: thumbSize
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.35)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: .black.opacity(
                            colorScheme == .dark ? 0.45 : 0.22
                        ),
                        radius: 3,
                        y: 1
                    )
                    .offset(x: thumbOffset)
            }
            .frame(
                width: width,
                height: geo.size.height
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = min(
                            max(drag.location.x - thumbSize / 2, 0),
                            usableWidth
                        )

                        value = Double(x / usableWidth)
                    }
            )
        }
        .frame(height: thumbSize)
    }
}
