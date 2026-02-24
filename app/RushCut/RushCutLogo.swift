import SwiftUI

/// RushCut logo drawn from SVG paths. Adapts to light/dark mode automatically.
struct RushCutLogo: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvasSize in
            // Original SVG viewBox: 0 0 488 486
            let scale = min(canvasSize.width / 488, canvasSize.height / 486)
            let offsetX = (canvasSize.width - 488 * scale) / 2
            let offsetY = (canvasSize.height - 486 * scale) / 2

            var transform = CGAffineTransform.identity
                .translatedBy(x: offsetX, y: offsetY)
                .scaledBy(x: scale, y: scale)

            // Path 1: right shape
            let path1 = CGMutablePath()
            path1.move(to: CGPoint(x: 402.562, y: 66.126))
            path1.addLine(to: CGPoint(x: 162.371, y: 66.126))
            path1.addLine(to: CGPoint(x: 212.435, y: 153.462))
            path1.addCurve(to: CGPoint(x: 266.287, y: 137.774),
                           control1: CGPoint(x: 228.079, y: 143.527),
                           control2: CGPoint(x: 246.523, y: 137.774))
            path1.addCurve(to: CGPoint(x: 368.587, y: 242.483),
                           control1: CGPoint(x: 322.787, y: 137.774),
                           control2: CGPoint(x: 368.587, y: 184.654))
            path1.addCurve(to: CGPoint(x: 315.952, y: 334.022),
                           control1: CGPoint(x: 368.587, y: 281.860),
                           control2: CGPoint(x: 347.341, y: 316.142))
            path1.addLine(to: CGPoint(x: 402.562, y: 485.070))
            path1.addCurve(to: CGPoint(x: 487.109, y: 398.507),
                           control1: CGPoint(x: 449.261, y: 485.070),
                           control2: CGPoint(x: 487.109, y: 446.316))
            path1.addLine(to: CGPoint(x: 487.109, y: 152.672))
            path1.addCurve(to: CGPoint(x: 402.562, y: 66.126),
                           control1: CGPoint(x: 487.109, y: 104.872),
                           control2: CGPoint(x: 449.261, y: 66.126))
            path1.closeSubpath()

            // Path 2: left shape
            let path2 = CGMutablePath()
            path2.move(to: CGPoint(x: 266.287, y: 347.192))
            path2.addCurve(to: CGPoint(x: 163.985, y: 242.483),
                           control1: CGPoint(x: 209.787, y: 347.192),
                           control2: CGPoint(x: 163.985, y: 300.312))
            path2.addCurve(to: CGPoint(x: 186.227, y: 177.335),
                           control1: CGPoint(x: 163.985, y: 217.849),
                           control2: CGPoint(x: 172.318, y: 195.219))
            path2.addLine(to: CGPoint(x: 84.548, y: 0.000))
            path2.addCurve(to: CGPoint(x: 0, y: 86.546),
                           control1: CGPoint(x: 37.854, y: 0.000),
                           control2: CGPoint(x: 0, y: 38.753))
            path2.addLine(to: CGPoint(x: 0, y: 332.382))
            path2.addCurve(to: CGPoint(x: 84.548, y: 418.939),
                           control1: CGPoint(x: 0, y: 380.187),
                           control2: CGPoint(x: 37.854, y: 418.939))
            path2.addLine(to: CGPoint(x: 324.741, y: 418.939))
            path2.addLine(to: CGPoint(x: 282.813, y: 345.813))
            path2.addCurve(to: CGPoint(x: 266.287, y: 347.192),
                           control1: CGPoint(x: 277.432, y: 346.707),
                           control2: CGPoint(x: 271.915, y: 347.192))
            path2.closeSubpath()

            // Path 3: center ring (eye/lens)
            let path3 = CGMutablePath()
            // Inner circle
            path3.move(to: CGPoint(x: 265.691, y: 267.402))
            path3.addCurve(to: CGPoint(x: 241.204, y: 242.339),
                           control1: CGPoint(x: 252.167, y: 267.402),
                           control2: CGPoint(x: 241.204, y: 256.182))
            path3.addCurve(to: CGPoint(x: 265.691, y: 217.274),
                           control1: CGPoint(x: 241.204, y: 228.496),
                           control2: CGPoint(x: 252.167, y: 217.274))
            path3.addCurve(to: CGPoint(x: 290.180, y: 242.339),
                           control1: CGPoint(x: 279.216, y: 217.274),
                           control2: CGPoint(x: 290.180, y: 228.496))
            path3.addCurve(to: CGPoint(x: 265.691, y: 267.402),
                           control1: CGPoint(x: 290.180, y: 256.182),
                           control2: CGPoint(x: 279.216, y: 267.402))
            path3.closeSubpath()
            // Outer circle
            path3.move(to: CGPoint(x: 265.691, y: 164.011))
            path3.addCurve(to: CGPoint(x: 189.167, y: 242.339),
                           control1: CGPoint(x: 223.428, y: 164.011),
                           control2: CGPoint(x: 189.167, y: 199.080))
            path3.addCurve(to: CGPoint(x: 265.691, y: 320.666),
                           control1: CGPoint(x: 189.167, y: 285.596),
                           control2: CGPoint(x: 223.428, y: 320.666))
            path3.addCurve(to: CGPoint(x: 342.218, y: 242.339),
                           control1: CGPoint(x: 307.957, y: 320.666),
                           control2: CGPoint(x: 342.218, y: 285.596))
            path3.addCurve(to: CGPoint(x: 265.691, y: 164.011),
                           control1: CGPoint(x: 342.218, y: 199.080),
                           control2: CGPoint(x: 307.957, y: 164.011))
            path3.closeSubpath()

            let p1 = Path(path1).applying(transform)
            let p2 = Path(path2).applying(transform)
            let p3 = Path(path3).applying(transform)

            context.fill(p1, with: .foreground)
            context.fill(p2, with: .foreground)
            // Use even-odd rule for the ring (donut shape)
            context.fill(p3, with: .foreground, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .padding(size * 0.1)
    }
}
