//
//  MeetingView.swift
//  Learning
//
//  Created by Guru on 23/07/26.
//

import SwiftUI
import UIKit

/// Replicates Android Audio Meeting screen controls and chrome.
struct MeetingView: View {
    @StateObject var viewModel: MeetingViewModel
    @State private var cloudShareItem: CloudSharePayload?
    @State private var refreshSpinAngle: Double = 0
    @State private var isRecordingOptionsExpanded = false

    var body: some View {
        Group {
            if viewModel.isWaitingForHost {
                waitingForHostView
            } else {
                VStack(spacing: 0) {
                    if let badge = viewModel.localHostSessionBadgeText {
                        HStack {
                            Text(badge)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .background(AppColors.meetingBackground)
                    }
                    topBar
                        .zIndex(20)
                    if let statusMessage = viewModel.statusBannerMessage {
                        HostStatusBanner(
                            message: statusMessage,
                            onDismiss: { viewModel.dismissStatusBanner() }
                        )
                        .zIndex(20)
                    }
                    mainContent
                        .zIndex(0)
                    hostExpirySection
                        .zIndex(10)
                    bottomControls
                        .zIndex(10)
                }
            }
        }
        .background(AppColors.meetingBackground.ignoresSafeArea())
        .sheet(isPresented: $viewModel.showParticipants) {
            participantsSheet
        }
        .sheet(item: $cloudShareItem) { payload in
            CloudActivityView(activityItems: [payload.text])
        }
        .overlay {
            if viewModel.showSettings {
                hostSettingsOverlay
                    .zIndex(90)
            }
            if viewModel.showCloudRecordings {
                cloudRecordingsSheet
                    .zIndex(85)
            }
            if viewModel.showRecordings {
                recordingsSheet
                    .zIndex(80)
            }
            if viewModel.showLogoutAllConfirm {
                WarningDialog(
                    title: "Logout All Users",
                    message: "Are you sure you want to logout all participants?",
                    confirmTitle: "Yes",
                    onCancel: { viewModel.cancelLogoutAll() },
                    onConfirm: { viewModel.confirmLogoutAll() }
                )
            } else if viewModel.showEndMeetingConfirm {
                WarningDialog(
                    title: "End Meeting",
                    message: "Are you sure you want to end this meeting for everyone ?",
                    confirmTitle: "Yes",
                    onCancel: { viewModel.cancelEndMeeting() },
                    onConfirm: { viewModel.confirmEndMeeting() }
                )
            } else if viewModel.showLeaveMeetingConfirm {
                WarningDialog(
                    title: "Leave Meeting",
                    message: "Are you sure you want to leave this meeting?",
                    confirmTitle: "Yes",
                    onCancel: { viewModel.cancelLeaveMeeting() },
                    onConfirm: { viewModel.confirmLeaveMeeting() }
                )
            } else if viewModel.showStatusSheet {
                StatusBroadcastDialog(
                    message: $viewModel.statusMessageDraft,
                    onCancel: { viewModel.cancelStatus() },
                    onSend: { viewModel.sendStatus() }
                )
            } else if viewModel.showMeetingRecordingNotice && !viewModel.isWaitingForHost {
                MeetingRecordingNoticeDialog(
                    onAcknowledge: { viewModel.dismissMeetingRecordingNotice() }
                )
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
        .animation(.easeInOut(duration: 0.2), value: viewModel.showLogoutAllConfirm)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showEndMeetingConfirm)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showLeaveMeetingConfirm)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showStatusSheet)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showMeetingRecordingNotice)
        .animation(.easeInOut(duration: 0.2), value: viewModel.participantMenuTarget?.id)
        .animation(.easeInOut(duration: 0.2), value: viewModel.statusBannerMessage)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showFloatingMenu)
    }

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
                    Text("Waiting for host to start the meeting")
                        .font(AppFonts.headline(20))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("You'll be connected automatically once the host begins.")
                        .font(AppFonts.body(14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    viewModel.leave()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.down.fill")
                        Text("Leave")
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

    private var topBar: some View {
        // Android: when someone speaks, a white strip (always white, even in dark) shows
        // speaker chips above a slim navy Participants row. When idle, only the navy row
        // (extended into the status-bar safe area).
        VStack(spacing: 0) {
            if !viewModel.activeSpeakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.activeSpeakers, id: \.id) { speaker in
                            Text(speaker.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .background(Color.white)
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    viewModel.showParticipants = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Participants (\(viewModel.participantCount))")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                HStack(alignment: .center, spacing: 14) {
                    if viewModel.connectionState == .connected {
                        Image("rec-button")
                            .resizable()
                            .frame(width: 20, height: 20)
                           // .foregroundStyle(AppColors.muteRed)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Recording")
                    }

                    // 3 icons: spinning refresh while 0 participants → host network after someone speaks.
                    if viewModel.participantCount == 0 || !viewModel.showHostNetworkInHeader {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(refreshSpinAngle))
                            .onAppear { startRefreshSpin() }
                            .onChange(of: viewModel.participantCount) { _, count in
                                if count == 0 { startRefreshSpin() }
                            }
                            .allowsHitTesting(false)
                    } else {
                        // Host's own live Zoom audio network (not a static image).
                        NetworkSignalView(quality: viewModel.networkQuality)
                    }
                    // Current audio route status (not a toggle) — mirrors Android header icon.
                    Image(systemName: viewModel.isEarphoneMode ? "headphones" : "speaker.wave.2.fill")
                        .foregroundStyle(AppColors.speakerGreen)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isEarphoneMode)
                    // Status-only — not tappable; mute is controlled from the bottom mic button.
                    Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(viewModel.isMuted ? AppColors.muteRed : AppColors.speakerGreen)
                        .allowsHitTesting(false)
                }
                .font(.system(size: 16, weight: .semibold))
                .animation(.easeInOut(duration: 0.2), value: viewModel.showHostNetworkInHeader)
                .animation(.easeInOut(duration: 0.2), value: viewModel.participantCount)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.navy)
        }
        .frame(maxWidth: .infinity)
        .background {
            Group {
                if viewModel.activeSpeakers.isEmpty {
                    AppColors.navy
                } else {
                    Color.white
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        // Avoid animating white↔navy chrome — that reads as a blink.
        .animation(nil, value: viewModel.activeSpeakerNames)
    }

    private func startRefreshSpin() {
        refreshSpinAngle = 0
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            refreshSpinAngle = 360
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .trailing) {
            if viewModel.remoteParticipants.isEmpty {
                VStack {
                    Text(viewModel.emptyBannerText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 16)
                        .background(AppColors.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    Spacer()
                }
            } else {
                participantGrid
            }

            VStack {
                if viewModel.showFloatingMenu {
                    floatingMenuPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .padding(.top, 16)
                        .padding(.trailing, 10)
                }
                Spacer()
                pullTab
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.meetingBackground)
        // Keep participant cards/menus from drawing over the Participants header.
        .clipped()
        // Tap empty meeting area to dismiss participant menu.
        .onTapGesture {
            if viewModel.participantMenuTarget != nil {
                viewModel.dismissParticipantMenu()
            }
        }
    }

    // MARK: - Right side floating menu

    private var pullTab: some View {
        Button {
            viewModel.toggleFloatingMenu()
        } label: {
            Image(systemName: viewModel.showFloatingMenu ? "xmark" : "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 22, height: 54)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(AppColors.sideTab)
                )
        }
    }

    private var floatingMenuPanel: some View {
        VStack(spacing: 10) {
            floatingMenuItem(title: "Recording", icon: "music.note.list", color: AppColors.speakerGreen) {
                viewModel.openRecordings()
            }
            floatingMenuItem(title: "Status", icon: "message.fill", color: Color.blue) {
                viewModel.openStatus()
            }
            floatingMenuItem(title: "Cloud", icon: "cloud.fill", color: AppColors.muteRed) {
                viewModel.openCloudRecordings()
            }
            floatingMenuItem(title: "Settings", icon: "gearshape.fill", color: Color.cyan) {
                viewModel.openSettings()
            }
        }
        .padding(10)
        .background(AppColors.sideTab.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func floatingMenuItem(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(AppFonts.button(12))
            }
            .foregroundStyle(.white)
            .frame(width: 76, height: 62)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Participant grid

    private var participantGrid: some View {
        ScrollView {
            // Android: fixed 3 compact columns (no force-fit for 27).
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(viewModel.displayParticipants) { participant in
                    participantCard(participant)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .padding(.bottom, viewModel.participantMenuTarget == nil ? 0 : 150)
        }
    }

    private func participantCard(_ participant: MeetingParticipant) -> some View {
        let state = viewModel.cardState(for: participant)
        let showMenu = viewModel.participantMenuTarget?.id == participant.id
        let isUnlistened = viewModel.isUnlistenedByHost(participant)
        let isHostPeer = viewModel.isHostCoHostPeer(participant)
        let hostPeerSpeaking = viewModel.isHostCoHostSpeaking(participant)

        return ZStack(alignment: .top) {
            VStack(spacing: 4) {
                Text(viewModel.displayName(for: participant))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(AppColors.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(isHostPeer ? "-" : (viewModel.username(for: participant) ?? "-"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(AppColors.black)
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(cardColor(for: state, participant: participant))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if viewModel.settings.usersNetwork {
                    NetworkSignalView(quality: viewModel.networkQuality(for: participant))
                        .scaleEffect(0.65)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .top) {
            if showMenu {
                ParticipantActionMenu(
                    isUnlistened: isUnlistened,
                    onRemove: { viewModel.removeParticipantFromMenu() },
                    onUnlistenToggle: { viewModel.toggleUnlistenFromMenu() },
                    onDismiss: { viewModel.dismissParticipantMenu() }
                )
                // Card is 72pt tall; open just below it so the card stays visible.
                .offset(y: 78)
            }
        }
        .onTapGesture {
            if viewModel.participantMenuTarget != nil {
                viewModel.dismissParticipantMenu()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            viewModel.openParticipantMenu(participant)
        }
        .zIndex(showMenu ? 40 : 0)
        .animation(.easeInOut(duration: 0.2), value: hostPeerSpeaking)
        .animation(.easeInOut(duration: 0.2), value: state == .speaking)
        .animation(.easeInOut(duration: 0.2), value: participant.isMuted)
        .animation(.easeInOut(duration: 0.2), value: state == .joining)
        .animation(.easeInOut(duration: 0.2), value: state == .paused)
        .animation(.easeInOut(duration: 0.2), value: state == .handsfree)
        .animation(.easeInOut(duration: 0.15), value: showMenu)
    }

    private func cardColor(for state: MeetingViewModel.ParticipantCardState, participant: MeetingParticipant) -> Color {
        if viewModel.isHostCoHostPeer(participant) {
            switch state {
            case .speaking:
                return AppColors.participantCardCohostIdle
            default:
                return AppColors.participantCardHostCohostSpeaking
            }
        }
        switch state {
        case .joining, .handsfree:
            return AppColors.participantCardYellow
        case .speaking:
            return AppColors.participantCardSpeaking
        case .paused:
            return AppColors.participantCardPurple
        case .idle:
            return AppColors.participantCardGreen
        }
    }

    private var hostExpirySection: some View {
        VStack(spacing: 0) {
            if viewModel.showPaymentPendingBanner {
                paymentPendingMarquee
            }
            expiryBar
        }
    }

    /// Competitor-style red scrolling ticker, directly above the Expires-in bar.
    private var paymentPendingMarquee: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let minutes = viewModel.displayRemainingMinutes(at: context.date)
            let message =
                "Your Zoom account payment is pending. Meeting will work for \(minutes) minutes only."
            ScrollingMarqueeText(text: message)
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background(AppColors.navy)
        }
    }

    private var expiryBar: some View {
        HStack {
            Text(viewModel.expiryDaysText)
            Spacer()
            Text(viewModel.expiryDateText)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(AppColors.expiryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(AppColors.expiryBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.expiryDivider)
                .frame(height: 2)
        }
    }

    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 8) {
                controlButton(title: "Listen All", icon: "person.wave.2.fill", color: .black) {
                    viewModel.listenAll()
                }
                controlButton(title: "Logout All", icon: "person.badge.minus", color: .black) {
                    viewModel.requestLogoutAll()
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.toggleMute()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(viewModel.isMuted ? Color.black : AppColors.speakerGreen)
                        .frame(width: 74, height: 74)
                    Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(viewModel.isMuted ? AppColors.muteRed : .white)
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isMuted)

            VStack(spacing: 8) {
                controlButton(
                    title: viewModel.isEarphoneMode ? "Earphone" : "Speaker",
                    icon: viewModel.isEarphoneMode ? "headphones" : "speaker.wave.2.fill",
//                    title: viewModel.isEarphoneMode ? "Speaker" : "Earphone",
//                    icon: viewModel.isEarphoneMode ? "speaker.wave.2.fill" : "headphones",
                    color: .black
                ) {
                    viewModel.toggleEarphone()
                }
                controlButton(title: viewModel.endLeaveButtonTitle, icon: "phone.down.fill", color: AppColors.endRed) {
                    viewModel.requestEndMeeting()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(AppColors.navy.ignoresSafeArea(edges: .bottom))
    }

    private func controlButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Participants sheet

    private var participantsSheet: some View {
        NavigationStack {
            Group {
                if viewModel.remoteParticipants.isEmpty {
                    EmptyStateView(
                        title: "No Participants Connected",
                        message: "Participants will appear here when they join the audio session."
                    )
                } else {
                    List(viewModel.remoteParticipants) { participant in
                        HStack {
                            Text(viewModel.displayName(for: participant))
                            Spacer()
                            Image(systemName: participant.isMuted ? "mic.slash" : "mic")
                                .foregroundStyle(participant.isMuted ? AppColors.muteRed : AppColors.speakerGreen)
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { viewModel.showParticipants = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Recordings sheet (host's local recordings)

    private var recordingsSheet: some View {
        LocalRecordingsPanel(
            isEmpty: viewModel.recordings.isEmpty,
            emptyMessage: "Recordings captured during this session will appear here.",
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
        .onAppear { viewModel.reloadLocalRecordings() }
        .transaction { $0.animation = nil }
    }

    // MARK: - Cloud recordings sheet

    private var cloudRecordingsSheet: some View {
        CloudRecordingsPanel(
            state: viewModel.cloudRecordings.state,
            onClose: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.showCloudRecordings = false
                }
            },
            onRetry: { Task { await viewModel.cloudRecordings.load() } },
            onPlay: { item in
                if let url = item.openURL {
                    UIApplication.shared.open(url)
                }
            },
            onShare: { item in
                cloudShareItem = CloudSharePayload(text: item.shareMessage)
            }
        )
        .onAppear {
            Task { await viewModel.cloudRecordings.load() }
        }
        .transaction { $0.animation = nil }
    }
    // MARK: - Settings overlay (Android modal)

    private var hostSettingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    isRecordingOptionsExpanded = false
                    viewModel.showSettings = false
                }

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
                        title: "Users Shuffling",
                        subtitle: "Speaking participants on top",
                        isOn: Binding(
                            get: { viewModel.settings.usersShuffling },
                            set: { viewModel.settings.usersShuffling = $0 }
                        )
                    )
                    settingsToggleRow(
                        title: "Users Network",
                        subtitle: "Show users network indicator",
                        isOn: Binding(
                            get: { viewModel.settings.usersNetwork },
                            set: { viewModel.settings.usersNetwork = $0 }
                        )
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recording System")
                            .font(AppFonts.bodyBold(15))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Try recording from this system")
                            .font(AppFonts.caption(13))
                            .foregroundStyle(AppColors.textSecondary)

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
                                    ForEach(HostMeetingSettingsStore.recordingSystemOptions, id: \.self) { option in
                                        Button {
                                            viewModel.settings.recordingSystem = option
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

                                        if option != HostMeetingSettingsStore.recordingSystemOptions.last {
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
                    isRecordingOptionsExpanded = false
                    viewModel.showSettings = false
                } label: {
                    Text("Close")
                        .font(AppFonts.button(16))
                        .foregroundStyle(AppColors.primaryButtonForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppColors.primaryButtonBackground)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 28)
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
                .toggleStyle(AndroidSettingsToggleStyle())
        }
    }
}

/// Host Settings switch — light: black/white; dark: cyan + navy (Android).
private struct AndroidSettingsToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let onTrack = isDark ? AppColors.accentBlue : Color.black
        let offTrack = isDark ? Color.gray.opacity(0.35) : Color(white: 0.82)
        let onThumb = isDark ? AppColors.navy : Color.white
        let offThumb = isDark ? AppColors.navy : Color(white: 0.45)

        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? onTrack : offTrack)
                    .frame(width: 51, height: 31)
                    .overlay {
                        if !configuration.isOn, !isDark {
                            Capsule()
                                .stroke(Color(white: 0.55), lineWidth: 1)
                        }
                    }

                Circle()
                    .fill(configuration.isOn ? onThumb : offThumb)
                    .frame(width: 27, height: 27)
                    .padding(2)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            }
            .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// Android-style long-press menu — larger, floats over/outside the card.
private struct ParticipantActionMenu: View {
    let isUnlistened: Bool
    let onRemove: () -> Void
    let onUnlistenToggle: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                menuRow(
                    title: "Remove",
                    systemImage: "xmark",
                    iconColor: AppColors.muteRed,
                    action: onRemove
                )

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.leading, 36)

                menuRow(
                    title: isUnlistened ? "Unmute" : "Mute",
                    systemImage: isUnlistened ? "ear" : "speaker.slash.fill",
                    iconColor: Color(red: 80 / 255, green: 150 / 255, blue: 1),
                    action: onUnlistenToggle
                )
            }
            .frame(width: 132)
            .background(Color(red: 45 / 255, green: 40 / 255, blue: 38 / 255).opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 30, height: 30)
                    .background(Color(red: 45 / 255, green: 40 / 255, blue: 38 / 255).opacity(0.96))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func menuRow(
        title: String,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.92, blue: 0.92))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Centered warning dialog — Logout All / End Meeting (Android light + dark).
private struct WarningDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
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
        // Dark theme: keep cancel readable (was too muted/dark).
        colorScheme == .dark ? Color.white.opacity(0.92) : AppColors.black
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(iconColor)
                    .padding(.top, 4)

                Text(title)
                    .font(AppFonts.headline(20))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppFonts.body(15))
                    .foregroundStyle(AppColors.textPrimary.opacity(colorScheme == .dark ? 0.85 : 0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                HStack(spacing: 70) {
                    Button("No", action: onCancel)
                        .font(AppFonts.button(16))
                        .foregroundStyle(cancelColor)

                    Button(confirmTitle, action: onConfirm)
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

/// "Send Status to All" broadcast dialog (Android light + dark).
private struct StatusBroadcastDialog: View {
    @Binding var message: String
    let onCancel: () -> Void
    let onSend: () -> Void

    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var iconColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    private var sendColor: Color {
        colorScheme == .dark ? AppColors.accentBlue : AppColors.black
    }

    private var cancelColor: Color {
        // Dark theme: Cancel was too dark — use bright white.
        colorScheme == .dark ? Color.white : AppColors.black
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.40)
                .ignoresSafeArea()
                .onTapGesture {
                    if isFieldFocused {
                        isFieldFocused = false
                    } else {
                        onCancel()
                    }
                }

            VStack(spacing: 14) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(iconColor)
                    .padding(.top, 4)

                Text("Send Status to All")
                    .font(AppFonts.headline(20))
                    .foregroundStyle(AppColors.textPrimary)

                TextField("Type your status", text: $message)
                    .font(AppFonts.body(15))
                    .foregroundStyle(AppColors.textPrimary)
                    .tint(iconColor)
                    .focused($isFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard canSend else { return }
                        isFieldFocused = false
                        onSend()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppColors.fieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isFieldFocused ? iconColor : AppColors.fieldBorder,
                                lineWidth: isFieldFocused ? 1.5 : 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 70) {
                    Button("Cancel") {
                        isFieldFocused = false
                        onCancel()
                    }
                    .font(AppFonts.button(16))
                    .foregroundStyle(cancelColor)

                    Button("Send") {
                        isFieldFocused = false
                        onSend()
                    }
                    .font(AppFonts.button(16))
                    .fontWeight(.bold)
                    .foregroundStyle(sendColor)
                    .opacity(canSend ? 1 : 0.4)
                    .disabled(!canSend)
                }
                .padding(.top, 8)
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
            .contentShape(Rectangle())
            .onTapGesture {
                isFieldFocused = false
            }
        }
        .transition(.opacity)
    }
}
