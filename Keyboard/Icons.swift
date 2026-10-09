import UIKit

/// 디자인에 그린 선 아이콘을 앱 안에서 그대로 그린다.
/// 좌표는 디자인과 같은 24×24 기준이고, 색은 버튼의 tintColor 를 따른다.
enum Icon {

    /// - Parameters:
    ///   - size: 아이콘 높이(pt)
    ///   - line: 24 기준에서의 선 굵기 (디자인의 stroke-width)
    static func image(_ name: String, size: CGFloat, line: CGFloat = 2) -> UIImage {
        let boxWidth: CGFloat = name == "space" ? 30 : 24
        let scale = size / 24
        let canvas = CGSize(width: boxWidth * scale, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            c.scaleBy(x: scale, y: scale)
            UIColor.black.setStroke()
            UIColor.black.setFill()
            draw(name, line: line, in: c)
        }
        return img.withRenderingMode(.alwaysTemplate)
    }

    /// 자판 키에 쓰는 아이콘
    static func key(_ symbol: String) -> UIImage {
        switch symbol {
        case "delete.left": return image("backspace", size: 24)
        case "shift.fill": return image("shift.fill", size: 22)
        case "capslock.fill": return image("shift.lock", size: 22)
        case "shift": return image("shift", size: 22)
        default: return image(symbol, size: 24)
        }
    }

    // MARK: - 그리기

    private static func stroke(_ p: UIBezierPath, _ line: CGFloat) {
        p.lineWidth = line
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    private static func poly(_ pts: [(CGFloat, CGFloat)], close: Bool = false) -> UIBezierPath {
        let p = UIBezierPath()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: pt.0, y: pt.1)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        if close { p.close() }
        return p
    }

    private static func draw(_ name: String, line: CGFloat, in c: CGContext) {
        switch name {
        case "clipboard":
            stroke(UIBezierPath(roundedRect: CGRect(x: 5, y: 4, width: 14, height: 17), cornerRadius: 2), line)
            stroke(UIBezierPath(roundedRect: CGRect(x: 9, y: 2, width: 6, height: 4), cornerRadius: 1), line)
            stroke(poly([(9, 11), (15, 11)]), line)
            stroke(poly([(9, 15), (15, 15)]), line)

        case "plus":
            stroke(poly([(12, 5), (12, 19)]), line)
            stroke(poly([(5, 12), (19, 12)]), line)

        case "smile":
            stroke(UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 18, height: 18)), line)
            let m = UIBezierPath()
            m.move(to: CGPoint(x: 8.5, y: 14.5))
            m.addQuadCurve(to: CGPoint(x: 15.5, y: 14.5), controlPoint: CGPoint(x: 12, y: 18))
            stroke(m, line)
            UIBezierPath(ovalIn: CGRect(x: 8, y: 8.5, width: 2, height: 2)).fill()
            UIBezierPath(ovalIn: CGRect(x: 14, y: 8.5, width: 2, height: 2)).fill()

        case "undo":
            // 되돌리기: 왼쪽 화살촉과 돌아 나오는 선
            stroke(poly([(9, 14), (4, 9), (9, 4)]), line)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 4, y: 9))
            p.addLine(to: CGPoint(x: 14, y: 9))
            p.addArc(withCenter: CGPoint(x: 14, y: 15), radius: 6, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
            p.addLine(to: CGPoint(x: 11, y: 21))
            stroke(p, line)

        case "slider.horizontal.3":
            stroke(poly([(4, 7), (14, 7)]), line)
            stroke(poly([(18, 7), (20, 7)]), line)
            stroke(poly([(4, 17), (6, 17)]), line)
            stroke(poly([(10, 17), (20, 17)]), line)
            stroke(UIBezierPath(ovalIn: CGRect(x: 14, y: 5, width: 4, height: 4)), line)
            stroke(UIBezierPath(ovalIn: CGRect(x: 6, y: 15, width: 4, height: 4)), line)

        case "pin", "pin.fill":
            // 압정을 30도 기울인다
            c.translateBy(x: 12, y: 12)
            c.rotate(by: .pi / 6)
            c.translateBy(x: -12, y: -12)
            let head = poly([(9, 3), (15, 3), (14, 9), (18, 13), (6, 13), (10, 9)], close: true)
            if name == "pin.fill" { head.fill() }
            stroke(head, line)
            stroke(poly([(12, 13), (12, 21)]), line)

        case "trash":
            stroke(poly([(4, 7), (20, 7)]), line)
            stroke(poly([(9, 7), (9, 4), (15, 4), (15, 7)]), line)
            stroke(poly([(6, 7), (7, 20), (17, 20), (18, 7)]), line)
            stroke(poly([(10, 11), (10, 17)]), line)
            stroke(poly([(14, 11), (14, 17)]), line)

        case "chevron.left":
            stroke(poly([(15, 5), (8, 12), (15, 19)]), line)

        case "chevron.up":
            stroke(poly([(5, 15), (12, 8), (19, 15)]), line)

        case "chevron.down":
            stroke(poly([(5, 9), (12, 16), (19, 9)]), line)

        case "chevron.right":
            stroke(poly([(9, 5), (16, 12), (9, 19)]), line)

        case "backspace":
            let body = UIBezierPath()
            body.move(to: CGPoint(x: 9, y: 5))
            body.addLine(to: CGPoint(x: 20, y: 5))
            body.addQuadCurve(to: CGPoint(x: 21, y: 6), controlPoint: CGPoint(x: 21, y: 5))
            body.addLine(to: CGPoint(x: 21, y: 18))
            body.addQuadCurve(to: CGPoint(x: 20, y: 19), controlPoint: CGPoint(x: 21, y: 19))
            body.addLine(to: CGPoint(x: 9, y: 19))
            body.addLine(to: CGPoint(x: 3, y: 12))
            body.close()
            stroke(body, line)
            stroke(poly([(12, 9), (17, 15)]), line)
            stroke(poly([(17, 9), (12, 15)]), line)

        case "return":
            let bend = UIBezierPath()
            bend.move(to: CGPoint(x: 20, y: 5))
            bend.addLine(to: CGPoint(x: 20, y: 13))
            bend.addQuadCurve(to: CGPoint(x: 18, y: 15), controlPoint: CGPoint(x: 20, y: 15))
            bend.addLine(to: CGPoint(x: 5, y: 15))
            stroke(bend, line)
            stroke(poly([(9, 11), (5, 15), (9, 19)]), line)

        case "space":
            stroke(poly([(4, 10), (4, 15), (26, 15), (26, 10)]), line)

        case "shift", "shift.fill", "shift.lock":
            let arrow = poly([(12, 4), (20, 13), (15, 13), (15, 19), (9, 19), (9, 13), (4, 13)], close: true)
            if name != "shift" { arrow.fill() }
            stroke(arrow, line)
            if name == "shift.lock" { stroke(poly([(8, 22.5), (16, 22.5)]), line) }

        case "keyboard.down":
            stroke(UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 18, height: 11), cornerRadius: 2), line)
            stroke(poly([(7, 8), (7.01, 8)]), line)
            stroke(poly([(11, 8), (11.01, 8)]), line)
            stroke(poly([(15, 8), (15.01, 8)]), line)
            stroke(poly([(8, 11.5), (16, 11.5)]), line)
            stroke(poly([(9, 19), (12, 22), (15, 19)]), line)

        case "star.outline":
            stroke(poly([(12, 3), (14.7, 8.6), (20.8, 9.4), (16.3, 13.7), (17.4, 19.8), (12, 17),
                         (6.6, 19.8), (7.7, 13.7), (3.2, 9.4), (9.3, 8.6)], close: true), line)

        case "star":
            poly([(12, 3), (14.7, 8.6), (20.8, 9.4), (16.3, 13.7), (17.4, 19.8), (12, 17),
                  (6.6, 19.8), (7.7, 13.7), (3.2, 9.4), (9.3, 8.6)], close: true).fill()

        case "search":
            stroke(UIBezierPath(ovalIn: CGRect(x: 4.5, y: 4.5, width: 13, height: 13)), line)
            stroke(poly([(15.5, 15.5), (20, 20)]), line)

        case "check":
            stroke(poly([(5, 12.5), (10, 17.5), (19, 7)]), line)

        case "xmark":
            stroke(poly([(6, 6), (18, 18)]), line)
            stroke(poly([(18, 6), (6, 18)]), line)

        default:
            break
        }
    }
}
