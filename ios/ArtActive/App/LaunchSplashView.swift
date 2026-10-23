import SwiftUI

/// Заставка запуска: фирменная «А» прорисовывается штрихами в порядке логотипа —
/// фиолетовый с градиентом снизу вверх, жёлтый от вершины вниз, перекладина, —
/// затем пружинная «посадка» с тактильной отдачей и плавный переход в приложение.
/// С «Уменьшением движения» буква просто появляется. Геометрия — из LogoMark.svg.
struct LaunchSplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var purple: CGFloat = 0
    @State private var yellow: CGFloat = 0
    @State private var bar: CGFloat = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    private static let draw = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)

    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()
            LogoMarkStrokes(purple: purple, yellow: yellow, bar: bar)
                .frame(width: 112, height: 112)
                .scaleEffect(scale)
        }
        .opacity(opacity)
        .accessibilityHidden(true)
        .task { reduceMotion ? await appearStatically() : await playAnimation() }
    }

    private func playAnimation() async {
        Haptics.prepare(.splashStroke)
        await pause(120)

        Haptics.play(.splashStroke)
        withAnimation(Self.draw) { purple = 1 }
        await pause(320)

        Haptics.play(.splashStroke)
        withAnimation(Self.draw) { yellow = 1 }
        await pause(300)

        Haptics.prepare(.splashLand)
        withAnimation(.easeOut(duration: 0.2)) { bar = 1 }
        await pause(170)

        // «Посадка»: короткое сжатие и отскок — в этот момент отдача Taptic Engine.
        withAnimation(.easeIn(duration: 0.08)) { scale = 0.94 }
        await pause(80)
        Haptics.play(.splashLand)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.42)) { scale = 1.06 }
        await pause(150)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { scale = 1 }
        await pause(420)

        await dismiss(zoomOut: true)
    }

    private func appearStatically() async {
        purple = 1
        yellow = 1
        bar = 1
        Haptics.play(.splashLand)
        await pause(450)
        await dismiss(zoomOut: false)
    }

    private func dismiss(zoomOut: Bool) async {
        withAnimation(.easeInOut(duration: 0.32)) {
            opacity = 0
            if zoomOut { scale = 1.22 }
        }
        await pause(320)
        onFinish()
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// Три штриха буквы «А» с прогрессом прорисовки 0…1 каждого.
private struct LogoMarkStrokes: View {
    let purple: CGFloat
    let yellow: CGFloat
    let bar: CGFloat

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let style = StrokeStyle(lineWidth: LogoGeometry.strokeWidth * side / LogoGeometry.box, lineCap: .round)
            ZStack {
                // Порядок слоёв как в логотипе: перекладина, фиолетовый, жёлтый сверху.
                StrokeLine(from: LogoGeometry.barStart, to: LogoGeometry.barEnd)
                    .trim(from: 0, to: bar)
                    .stroke(LogoGeometry.violet, style: style)
                StrokeLine(from: LogoGeometry.purpleBottom, to: LogoGeometry.purpleTop)
                    .trim(from: 0, to: purple)
                    .stroke(
                        LinearGradient(
                            colors: [LogoGeometry.lilac, LogoGeometry.violet],
                            startPoint: UnitPoint(x: 0.1, y: 1),
                            endPoint: UnitPoint(x: 0.5, y: 0)
                        ),
                        style: style
                    )
                StrokeLine(from: LogoGeometry.yellowTop, to: LogoGeometry.yellowBottom)
                    .trim(from: 0, to: yellow)
                    .stroke(LogoGeometry.yellow, style: style)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Отрезок в координатах логотипа (viewBox 257.37), масштабируемый под рамку.
private struct StrokeLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / LogoGeometry.box
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + from.x * k, y: rect.minY + from.y * k))
        path.addLine(to: CGPoint(x: rect.minX + to.x * k, y: rect.minY + to.y * k))
        return path
    }
}

/// Осевые линии капсул из LogoMark.svg: ширина штриха 50.95 при viewBox 257.37.
private enum LogoGeometry {
    static let box: CGFloat = 257.37
    static let strokeWidth: CGFloat = 50.95

    static let purpleBottom = CGPoint(x: 25.8, y: 231.9)
    static let purpleTop = CGPoint(x: 128.3, y: 25.9)
    static let yellowTop = CGPoint(x: 128.7, y: 25.5)
    static let yellowBottom = CGPoint(x: 231.6, y: 231.9)
    static let barStart = CGPoint(x: 59.55, y: 186.6)
    static let barEnd = CGPoint(x: 127.49, y: 186.6)

    static let violet = Color(red: 0x6D / 255, green: 0x0F / 255, blue: 0xF2 / 255)
    static let lilac = Color(red: 0xB9 / 255, green: 0x9A / 255, blue: 0xD9 / 255)
    static let yellow = Color(red: 0xF2 / 255, green: 0xB8 / 255, blue: 0x07 / 255)
}
