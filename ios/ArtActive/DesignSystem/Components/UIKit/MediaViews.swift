import AVFoundation
import AVKit
import SafariServices
import SwiftUI
import UIKit

/// Веб-страница внутри приложения (сценарии, лендинги, кейсы).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(Palette.accent)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    /// SFSafariViewController принимает только http(s).
    static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// Видео с системными контролами (AVPlayerViewController): PiP, AirPlay, полноэкранный режим.
struct VideoPlayerController: UIViewControllerRepresentable {
    let url: URL
    var autoplay = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        context.coordinator.player = player
        if autoplay { player.play() }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
    }

    final class Coordinator {
        var player: AVPlayer?
    }
}

/// Фоновое видео без звука и контролов, по кругу (hero главной, шапка раздела, плитки).
/// `isPlaying = false` (вне экрана, Reduce Motion) — пауза, AVPlayerLayer показывает первый кадр.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var isPlaying = true

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.configure(url: url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL) {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            playerLayer?.player = queue
            playerLayer?.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        func setPlaying(_ playing: Bool) {
            if playing { player?.play() } else { player?.pause() }
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }
    }
}
