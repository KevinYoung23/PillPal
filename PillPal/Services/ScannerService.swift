import Foundation
import VisionKit
import UIKit

enum ScannerService {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    static func makeDemoPages() -> [UIImage] {
        [
            makePage(
                title: "Prescription Page 1",
                lines: [
                    "Patient: Jane Doe",
                    "Phone: 555-123-7890",
                    "Amoxicillin 500 mg tid x 7 days after meal",
                    "Eye drops 1 drop bid for 1 week"
                ]
            ),
            makePage(
                title: "Prescription Page 2",
                lines: [
                    "Storage: keep eye drops away from light",
                    "Follow-up: 2026-02-20",
                    "Complete full antibiotic course"
                ]
            )
        ]
    }

    private static func makePage(title: String, lines: [String]) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .left
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: titleStyle
            ]

            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .regular),
                .foregroundColor: UIColor.black
            ]

            title.draw(in: CGRect(x: 80, y: 100, width: 1040, height: 60), withAttributes: titleAttributes)

            for (index, line) in lines.enumerated() {
                line.draw(
                    in: CGRect(x: 80, y: 240 + CGFloat(index * 90), width: 1040, height: 70),
                    withAttributes: lineAttributes
                )
            }
        }
    }
}
