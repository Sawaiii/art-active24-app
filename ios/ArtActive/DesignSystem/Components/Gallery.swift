import SwiftUI

/// Элемент галереи: фото или видео с постером.
struct GalleryItem: Identifiable, Hashable {
    let id: Int
    let imageURL: URL?
    let videoURL: URL?

    static func from(_ media: [MediaItem]) -> [GalleryItem] {
        media.enumerated().compactMap { index, item -> GalleryItem? in
            switch item.type {
            case .video:
                return GalleryItem(id: index, imageURL: item.posterURL, videoURL: item.resolvedURL)
            case .image, .unknown:
                guard let url = item.resolvedURL else { return nil }
                return GalleryItem(id: index, imageURL: url, videoURL: nil)
            }
        }
    }

    static func from(urls: [String]) -> [GalleryItem] {
        urls.enumerated().compactMap { index, raw -> GalleryItem? in
            guard let url = raw.resolvedURL else { return nil }
            return GalleryItem(id: index, imageURL: url, videoURL: nil)
        }
    }
}

/// Точки-индикатор страниц (как на сайте: активная — акцент).
struct PageDots: View {
    let count: Int
    let current: Int
    var activeColor: Color = Palette.accent
    var inactiveColor: Color = Palette.bgTertiary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(count, 12), id: \.self) { index in
                Capsule()
                    .fill(index == current ? activeColor : inactiveColor)
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Фото \(current + 1) из \(count)"))
    }
}

/// Горизонтальный пейджинг галереи товара; тап — полноэкранный просмотр.
struct GalleryPager: View {
    let items: [GalleryItem]
    var aspectRatio: CGFloat = 1
    var badge: Badge?
    var cornerRadius: CGFloat = 0
    var imageBackground: Color = Palette.page

    @State private var selection = 0
    @State private var fullscreen: FullscreenRequest?
    @State private var video: VideoRequest?

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $selection) {
                ForEach(items) { item in
                    Button {
                        if let videoURL = item.videoURL {
                            video = VideoRequest(url: videoURL)
                        } else {
                            fullscreen = FullscreenRequest(index: selection)
                        }
                    } label: {
                        ZStack {
                            RemoteImage(url: item.imageURL, contentMode: .fit, maxPixel: 1200, placeholder: imageBackground)
                            if item.videoURL != nil {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Palette.textProduct)
                                    .frame(width: 56, height: 56)
                                    .brandGlass(in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(item.id)
                    .accessibilityLabel(item.videoURL == nil ? Text("Фото, открыть на весь экран") : Text("Видео, воспроизвести"))
                    .accessibilityIdentifier("gallery.item")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let badge { BadgeView(badge).padding(16) }
            }
            .onChange(of: selection) { _, _ in Haptics.play(.selection) }

            if items.count > 1 {
                PageDots(count: items.count, current: items.firstIndex { $0.id == selection } ?? 0)
            }
        }
        .onAppear { selection = items.first?.id ?? 0 }
        .fullScreenCover(item: $fullscreen) { request in
            FullscreenGallery(items: items.filter { $0.videoURL == nil }, startID: request.index) { lastID in
                selection = lastID
            }
        }
        .fullScreenCover(item: $video) { request in
            VideoScreen(url: request.url)
        }
    }

    struct FullscreenRequest: Identifiable { let index: Int; var id: Int { index } }
    struct VideoRequest: Identifiable { let url: URL; var id: String { url.absoluteString } }
}

/// Полноэкранная галерея: UIScrollView-зум, свайп вниз — закрыть с затуханием фона.
struct FullscreenGallery: View {
    let items: [GalleryItem]
    let startID: Int
    var onClose: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var dismissProgress: CGFloat = 0
    @State private var isZoomed = false

    init(items: [GalleryItem], startID: Int, onClose: @escaping (Int) -> Void = { _ in }) {
        self.items = items
        self.startID = startID
        self.onClose = onClose
        let valid = items.contains { $0.id == startID } ? startID : (items.first?.id ?? 0)
        _selection = State(initialValue: valid)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(Double(1 - dismissProgress * 0.8))
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(items) { item in
                    ZoomablePage(url: item.imageURL, onDismissProgress: { dismissProgress = $0 }, onDismiss: close, onZoomChange: { isZoomed = $0 })
                        .tag(item.id)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .scrollDisabled(isZoomed)

            HStack {
                if items.count > 1, let index = items.firstIndex(where: { $0.id == selection }) {
                    Text(verbatim: "\(index + 1) / \(items.count)")
                        .font(BrandFont.golos(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .brandGlass(in: Capsule(), tint: .black.opacity(0.2))
                }
                Spacer()
                GlassIconButton(systemName: "xmark", label: String(localized: "Закрыть"), action: close)
                    .accessibilityIdentifier("gallery.close")
            }
            .padding(.horizontal, 16)
            .opacity(Double(1 - dismissProgress))
        }
        .statusBarHidden()
        .onChange(of: selection) { _, _ in Haptics.play(.selection) }
        .accessibilityAction(.escape) { close() }
    }

    private func close() {
        onClose(selection)
        dismiss()
    }
}

/// Страница полноэкранной галереи — грузит картинку и отдаёт её UIScrollView.
private struct ZoomablePage: View {
    let url: URL?
    let onDismissProgress: (CGFloat) -> Void
    let onDismiss: () -> Void
    let onZoomChange: (Bool) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if image == nil {
                ProgressView().tint(.white)
            }
            ZoomableImageView(image: image, onDismissProgress: onDismissProgress, onDismiss: onDismiss, onZoomChange: onZoomChange)
        }
        .task(id: url) {
            guard let url else { return }
            image = try? await ImagePipeline.shared.image(for: url, maxPixel: 2400)
        }
    }
}

/// Экран видео (AVPlayerViewController).
struct VideoScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayerController(url: url).ignoresSafeArea()
            GlassIconButton(systemName: "xmark", label: String(localized: "Закрыть")) { dismiss() }
                .padding(16)
        }
    }
}
