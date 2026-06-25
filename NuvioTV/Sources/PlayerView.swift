import AVKit
import SwiftUI
import UIKit
@preconcurrency import VLCKit

struct PlayerView: View {
    @EnvironmentObject private var store: LibraryStore
    let source: MediaSource
    @State private var playbackError: String?
    @StateObject private var vlcPlayback: VLCPlaybackModel
    @State private var showsVLCControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    init(source: MediaSource) {
        self.source = source
        _vlcPlayback = StateObject(wrappedValue: VLCPlaybackModel(source: source))
    }

    var body: some View {
        ZStack {
            if source.playbackEngine == .vlc {
                VLCVideoSurface(playback: vlcPlayback)
                    .ignoresSafeArea()
                    .onAppear {
                        vlcPlayback.playbackError = $playbackError
                        revealVLCControls()
                    }

                if showsVLCControls || playbackError != nil {
                    VLCControlsOverlay(
                        source: source,
                        playback: vlcPlayback,
                        onInteraction: revealVLCControls
                    )
                    .transition(.opacity)
                }
            } else {
                NativePlayerController(
                    source: source,
                    playbackError: $playbackError
                ) {
                    store.closePlayer()
                }
                .ignoresSafeArea()
            }

            if let playbackError {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Playback failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline.weight(.bold))
                    Text(playbackError)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(errorRecoveryMessage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .padding(48)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsVLCControls)
        .onTapGesture {
            if source.playbackEngine == .vlc {
                revealVLCControls()
            }
        }
        .onPlayPauseCommand {
            if source.playbackEngine == .vlc {
                vlcPlayback.togglePlayPause()
                revealVLCControls()
            }
        }
        .onMoveCommand { direction in
            guard source.playbackEngine == .vlc else { return }
            switch direction {
            case .down:
                revealVLCControls()
            case .left:
                vlcPlayback.jumpBackward()
                revealVLCControls()
            case .right:
                vlcPlayback.jumpForward()
                revealVLCControls()
            default:
                break
            }
        }
        .onExitCommand {
            if source.playbackEngine == .vlc && showsVLCControls && playbackError == nil {
                hideControlsTask?.cancel()
                showsVLCControls = false
            } else {
                store.closePlayer()
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            if source.playbackEngine == .vlc {
                vlcPlayback.shutdown()
            }
        }
    }

    private var errorRecoveryMessage: String {
        switch source.playbackEngine {
        case .native:
            "Apple TV native playback works best with HLS or MP4. MKV/WebM/AVI sources are retried with VLC when detected."
        case .vlc:
            "This source was opened with the VLC fallback. Try another source if it still fails, especially a smaller file or an MP4/HLS stream."
        }
    }

    private func revealVLCControls() {
        showsVLCControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if playbackError == nil && vlcPlayback.isPlaying {
                    showsVLCControls = false
                }
            }
        }
    }
}

private struct VLCVideoSurface: UIViewRepresentable {
    @ObservedObject var playback: VLCPlaybackModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        playback.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        playback.attach(to: view)
    }
}

private struct VLCControlsOverlay: View {
    let source: MediaSource
    @ObservedObject var playback: VLCPlaybackModel
    let onInteraction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.title)
                        .font(.title2.weight(.bold))
                    Text(source.subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 56)
            .padding(.top, 44)

            Spacer()

            VStack(spacing: 20) {
                HStack {
                    Text(playback.elapsedText)
                        .font(.callout.monospacedDigit())
                    VLCTimelineView(progress: playback.progress)
                        .focusable()
                    Text(playback.durationText)
                        .font(.callout.monospacedDigit())
                }

                HStack(spacing: 28) {
                    Button {
                        playback.jumpBackward()
                        onInteraction()
                    } label: {
                        Label("Back 15", systemImage: "gobackward.15")
                    }

                    Button {
                        playback.togglePlayPause()
                        onInteraction()
                    } label: {
                        Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        playback.jumpForward()
                        onInteraction()
                    } label: {
                        Label("Forward 30", systemImage: "goforward.30")
                    }

                    Menu {
                        if playback.audioTracks.isEmpty {
                            Text("No audio tracks")
                        } else {
                            ForEach(playback.audioTracks) { track in
                                Button {
                                    playback.selectAudioTrack(track)
                                    onInteraction()
                                } label: {
                                    Label(track.name, systemImage: track.id == playback.selectedAudioTrackID ? "checkmark" : "speaker.wave.2")
                                }
                            }
                        }
                    } label: {
                        Label("Audio", systemImage: "speaker.wave.2.fill")
                    }

                    Menu {
                        if playback.subtitleTracks.isEmpty {
                            Text("No subtitles")
                        } else {
                            ForEach(playback.subtitleTracks) { track in
                                Button {
                                    playback.selectSubtitleTrack(track)
                                    onInteraction()
                                } label: {
                                    Label(track.name, systemImage: track.id == playback.selectedSubtitleTrackID ? "checkmark" : "captions.bubble")
                                }
                            }
                        }
                    } label: {
                        Label("Subtitles", systemImage: "captions.bubble.fill")
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 34)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.82), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .foregroundStyle(.white)
    }
}

private struct VLCTimelineView: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(height: 8)
                Capsule()
                    .fill(.white)
                    .frame(width: max(8, proxy.size.width * clampedProgress), height: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .offset(x: max(0, proxy.size.width * clampedProgress - 11))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 34)
        .contentShape(Rectangle())
    }
}

private struct VLCTrack: Identifiable, Equatable {
    let id: Int32
    let name: String
}

@MainActor
private final class VLCPlaybackModel: NSObject, ObservableObject, @preconcurrency VLCMediaPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var elapsedText = "0:00"
    @Published var durationText = "--:--"
    @Published var audioTracks: [VLCTrack] = []
    @Published var subtitleTracks: [VLCTrack] = []
    @Published var selectedAudioTrackID: Int32 = -1
    @Published var selectedSubtitleTrackID: Int32 = -1

    var playbackError: Binding<String?> = .constant(nil)

    private let source: MediaSource
    private let mediaPlayer = VLCMediaPlayer()
    private var didStart = false
    private var timer: Timer?

    init(source: MediaSource) {
        self.source = source
        super.init()
        mediaPlayer.delegate = self
    }

    func attach(to view: UIView) {
        guard !didStart else { return }
        didStart = true
        playbackError.wrappedValue = nil
        mediaPlayer.drawable = view
        mediaPlayer.scaleFactor = 0

        let media = VLCMedia(url: source.url)
        media.addOptions([
            "network-caching": 2000,
            "http-user-agent": "Mozilla/5.0 AppleTV NuvioTV/1.0"
        ])
        mediaPlayer.media = media
        mediaPlayer.play()
        startTimer()
    }

    func togglePlayPause() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
        refreshState()
    }

    func jumpBackward() {
        guard mediaPlayer.isSeekable else { return }
        mediaPlayer.jumpBackward(15)
        refreshTime()
    }

    func jumpForward() {
        guard mediaPlayer.isSeekable else { return }
        mediaPlayer.jumpForward(30)
        refreshTime()
    }

    func seek(to value: Double) {
        guard mediaPlayer.isSeekable else { return }
        mediaPlayer.position = Float(min(max(value, 0), 1))
        refreshTime()
    }

    func selectAudioTrack(_ track: VLCTrack) {
        mediaPlayer.currentAudioTrackIndex = Int32(track.id)
        refreshTracks()
    }

    func selectSubtitleTrack(_ track: VLCTrack) {
        mediaPlayer.currentVideoSubTitleIndex = Int32(track.id)
        refreshTracks()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        mediaPlayer.stop()
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        refreshState()
        refreshTracks()
        switch mediaPlayer.state {
        case .error:
            playbackError.wrappedValue = "VLC could not play this stream. Try another source or a smaller/transcoded source."
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        refreshTime()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
                self?.refreshTime()
            }
        }
    }

    private func refreshState() {
        isPlaying = mediaPlayer.isPlaying
    }

    private func refreshTime() {
        let elapsedMilliseconds = max(0, mediaPlayer.time.value?.doubleValue ?? 0)
        let durationMilliseconds = max(0, mediaPlayer.media?.length.value?.doubleValue ?? 0)
        elapsedText = Self.format(milliseconds: elapsedMilliseconds)
        durationText = durationMilliseconds > 0 ? Self.format(milliseconds: durationMilliseconds) : "--:--"
        if durationMilliseconds > 0 {
            progress = min(max(elapsedMilliseconds / durationMilliseconds, 0), 1)
        } else {
            progress = max(0, Double(mediaPlayer.position))
        }
    }

    private func refreshTracks() {
        audioTracks = Self.tracks(names: mediaPlayer.audioTrackNames, indexes: mediaPlayer.audioTrackIndexes)
        subtitleTracks = Self.tracks(names: mediaPlayer.videoSubTitlesNames, indexes: mediaPlayer.videoSubTitlesIndexes)
        selectedAudioTrackID = Int32(mediaPlayer.currentAudioTrackIndex)
        selectedSubtitleTrackID = Int32(mediaPlayer.currentVideoSubTitleIndex)
    }

    private static func tracks(names: [Any], indexes: [Any]) -> [VLCTrack] {
        zip(names, indexes).compactMap { name, index in
            guard let title = name as? String else { return nil }
            let trackID: Int32?
            if let number = index as? NSNumber {
                trackID = number.int32Value
            } else if let int = index as? Int {
                trackID = Int32(int)
            } else {
                trackID = nil
            }
            guard let trackID else { return nil }
            return VLCTrack(id: trackID, name: title)
        }
    }

    private static func format(milliseconds: Double) -> String {
        guard milliseconds.isFinite else { return "--:--" }
        let totalSeconds = max(0, Int(milliseconds / 1000))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    deinit {}
}

private struct NativePlayerController: UIViewControllerRepresentable {
    let source: MediaSource
    @Binding var playbackError: String?
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = makePlayer(context: context)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.playbackError = $playbackError
        if controller.player == nil {
            controller.player = makePlayer(context: context)
        }
        controller.player?.play()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackError: $playbackError, onClose: onClose)
    }

    private func makePlayer(context: Context) -> AVPlayer {
        let headers = [
            "User-Agent": "Mozilla/5.0 AppleTV NuvioTV/1.0",
            "Accept": "*/*"
        ]
        let asset = AVURLAsset(
            url: source.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = metadataItems
        let player = AVPlayer(playerItem: item)
        context.coordinator.observe(player: player, item: item)
        return player
    }

    private var metadataItems: [AVMetadataItem] {
        [
            metadataItem(identifier: .commonIdentifierTitle, value: source.title),
            metadataItem(identifier: .iTunesMetadataTrackSubTitle, value: source.subtitle)
        ]
        .compactMap { $0 }
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = trimmed as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var playbackError: Binding<String?>
        var onClose: () -> Void
        private var itemStatusObservation: NSKeyValueObservation?
        private var playerStatusObservation: NSKeyValueObservation?
        private var accessLogObserver: NSObjectProtocol?
        private var errorLogObserver: NSObjectProtocol?

        init(playbackError: Binding<String?>, onClose: @escaping () -> Void) {
            self.playbackError = playbackError
            self.onClose = onClose
        }

        func observe(player: AVPlayer, item: AVPlayerItem) {
            playbackError.wrappedValue = nil
            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                Task { @MainActor in
                    guard let self, let item, item.status == .failed else { return }
                    self.playbackError.wrappedValue = item.error?.localizedDescription ?? "The selected stream could not be decoded by AVPlayer."
                }
            }
            playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self, weak player] _, _ in
                Task { @MainActor in
                    guard let self, let player, player.status == .failed else { return }
                    self.playbackError.wrappedValue = player.error?.localizedDescription ?? "The player failed to load this stream."
                }
            }
            accessLogObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewErrorLogEntry,
                object: item,
                queue: .main
            ) { [weak self, weak item] _ in
                guard let self, let item else { return }
                let event = item.errorLog()?.events.last
                self.playbackError.wrappedValue = event?.errorComment ?? event?.errorStatusCode.description ?? "The stream returned a playback error."
            }
        }

        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            true
        }

        @MainActor
        func playerViewControllerWillEndFullScreenPresentation(_ playerViewController: AVPlayerViewController) {
            playerViewController.player?.pause()
            playerViewController.player?.replaceCurrentItem(with: nil)
            onClose()
        }

        deinit {
            if let accessLogObserver {
                NotificationCenter.default.removeObserver(accessLogObserver)
            }
            if let errorLogObserver {
                NotificationCenter.default.removeObserver(errorLogObserver)
            }
        }
    }
}
