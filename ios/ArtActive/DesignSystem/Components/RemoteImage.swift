import ImageIO
import SwiftUI
import UIKit

/// Память-кэш декодированных картинок (синхронный доступ — без мигания при повторном показе).
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// Загрузка картинок: URLCache на диске + даунсэмплинг ImageIO (WebP/JPEG/PNG) + память.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    static func key(_ url: URL, maxPixel: CGFloat) -> String { "\(url.absoluteString)#\(Int(maxPixel))" }

    func image(for url: URL, maxPixel: CGFloat) async throws -> UIImage {
        let key = Self.key(url, maxPixel: maxPixel)
        if let cached = ImageMemoryCache.shared.image(for: key) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let session = self.session
        let task = Task<UIImage, Error>.detached(priority: .utility) {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = Self.downsample(data, maxPixel: maxPixel) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        ImageMemoryCache.shared.insert(image, for: key)
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 64),
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Картинка из сети: заполняет предложенный размер, фон-подложка #F1F1F5,
/// плавное проявление 200 мс, опциональное превью низкого качества.
struct RemoteImage: View {
    let url: URL?
    var previewURL: URL?
    var contentMode: ContentMode = .fill
    var maxPixel: CGFloat = 900
    var placeholder: Color = Palette.imagePlaceholder
    /// Для .fill: если пропорция картинки отличается от пропорции ячейки больше чем на 12%
    /// (например, фото 800×600 вместо авы 600×600), показать целиком (.fit) на подложке — без обрезки.
    var fitWhenAspectDiffers: CGFloat?

    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    init(
        url: URL?,
        previewURL: URL? = nil,
        contentMode: ContentMode = .fill,
        maxPixel: CGFloat = 900,
        placeholder: Color = Palette.imagePlaceholder,
        fitWhenAspectDiffers: CGFloat? = nil
    ) {
        self.url = url
        self.previewURL = previewURL
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.placeholder = placeholder
        self.fitWhenAspectDiffers = fitWhenAspectDiffers
        let cached = url.flatMap { ImageMemoryCache.shared.image(for: ImagePipeline.key($0, maxPixel: maxPixel)) }
        _image = State(initialValue: cached)
    }

    var body: some View {
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: effectiveMode(for: image))
                        .transition(.opacity)
                } else if failed {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Palette.disabled)
                }
            }
            .clipped()
            .task(id: url) { await load() }
            .accessibilityHidden(true)
    }

    private func effectiveMode(for image: UIImage) -> ContentMode {
        guard contentMode == .fill, let target = fitWhenAspectDiffers, target > 0, image.size.height > 0 else {
            return contentMode
        }
        let actual = image.size.width / image.size.height
        return abs(actual - target) / target > 0.12 ? .fit : .fill
    }

    private func load() async {
        guard let url else {
            failed = true
            return
        }
        let key = ImagePipeline.key(url, maxPixel: maxPixel)
        if let cached = ImageMemoryCache.shared.image(for: key) {
            image = cached
            return
        }
        if image == nil, let previewURL,
           let preview = try? await ImagePipeline.shared.image(for: previewURL, maxPixel: 120) {
            image = preview
        }
        do {
            let loaded = try await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
            withAnimation(Motion.fast(reduceMotion)) { image = loaded }
            failed = false
        } catch {
            if !error.isCancellation, image == nil { failed = true }
        }
    }
}

/// Картинка с фиксированной пропорцией ячейки: ширина — доступная, высота — по `aspect` (ширина / высота).
/// Содержимое `.fill` (обрезка по краям) или `.fit` (целиком на подложке); всегда обрезано по форме.
/// Единый способ задавать размер картинок — вместо `frame(height:)`.
struct AspectImage: View {
    let url: URL?
    let aspect: CGFloat
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var maxPixel: CGFloat = 900
    var placeholder: Color = Palette.imagePlaceholder
    /// Не обрезать картинку другой пропорции (ава не найдена — пришло фото): показать целиком.
    var fitMismatched = false

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                RemoteImage(
                    url: url,
                    contentMode: contentMode,
                    maxPixel: maxPixel,
                    placeholder: placeholder,
                    fitWhenAspectDiffers: fitMismatched ? aspect : nil
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Пропорции исходников сайта (ширина / высота).
enum MediaAspect {
    /// Фото галерей, кейсы, фото залов, комплекты и допы — 800×600; площадки — 600×450.
    static let photo: CGFloat = 4 / 3
    /// Большая ава листинга — 600×600; карточки «Фишки», «Похожий персонал».
    static let square: CGFloat = 1
    /// Галерея и этапы программы (тимбилдинг) — 900×600, 380×253.
    static let wide: CGFloat = 3 / 2
    /// Мобильный баннер шапки шаблонов 81/123 — 430×768 (портрет).
    static let banner: CGFloat = 430.0 / 768.0
    /// Тарифы программы — 396×220.
    static let tier: CGFloat = 396.0 / 220.0
    /// Постер видео программы — 960×445.
    static let programVideo: CGFloat = 960.0 / 445.0
    /// Сезонные плитки главной — 535×305.
    static let promo: CGFloat = 535.0 / 305.0
    /// «Выгодные предложения» (акции) — 710×446.
    static let offer: CGFloat = 710.0 / 446.0
    /// Обложки кейсов в списке — 720×405 (16:9).
    static let caseCover: CGFloat = 720.0 / 405.0
    /// Плитки «Наши возможности» — низкая 305×175 и высокая 305×364.
    static let directionShort: CGFloat = 305.0 / 175.0
    static let directionTall: CGFloat = 305.0 / 364.0
}

private struct ViewportSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// Размер видимой области экрана-контейнера (для ограничения высоты портретных баннеров).
    var viewportSize: CGSize {
        get { self[ViewportSizeKey.self] }
        set { self[ViewportSizeKey.self] = newValue }
    }
}
