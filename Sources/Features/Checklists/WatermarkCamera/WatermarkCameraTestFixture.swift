#if DEBUG
import UIKit

/// Explicit UI-test fixture only; never substitutes for physical camera acceptance.
enum WatermarkCameraTestFixture {
    static func images() -> [UIImage] {
        [UIColor.systemGray4, UIColor.systemTeal].enumerated().map { index, color in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
                ("SITE TEST \(index + 1)" as NSString).draw(at: CGPoint(x: 100, y: 120), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 70), .foregroundColor: UIColor.black])
                UIColor.systemYellow.setStroke()
                context.cgContext.setLineWidth(10)
                context.cgContext.stroke(CGRect(x: 160, y: 260, width: 450, height: 280))
            }
        }
    }
}
#endif
