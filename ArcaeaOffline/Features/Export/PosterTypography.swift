import CoreText
import UIKit

/// Open-source families used by Arcaea Online, registered only for the export renderer.
@MainActor enum PosterTypography {
    enum Family { case exo, exo2, titillium, openSans }
    private static let names: [String: String] = {
        var result: [String: String] = [:]
        for file in ["Exo", "Exo2", "OpenSans", "TitilliumWeb-Regular", "TitilliumWeb-SemiBold", "TitilliumWeb-Bold"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String { result[file] = name }
        }
        return result
    }()
    static func font(_ family: Family, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let file: String
        switch family {
        case .exo: file = "Exo"
        case .exo2: file = "Exo2"
        case .openSans: file = "OpenSans"
        case .titillium: file = weight >= .bold ? "TitilliumWeb-Bold" : weight >= .medium ? "TitilliumWeb-SemiBold" : "TitilliumWeb-Regular"
        }
        guard let name = names[file], let base = UIFont(name: name, size: size) else { return .systemFont(ofSize: size, weight: weight) }
        if family == .titillium { return base }
        let axisWeight: CGFloat = weight >= .bold ? 700 : weight >= .semibold ? 600 : weight >= .medium ? 500 : weight <= .ultraLight ? 200 : weight <= .light ? 300 : 400
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([variation: [NSNumber(value: 0x77676874): axisWeight]])
        return UIFont(descriptor: descriptor, size: size)
    }
    static func potential(_ value: String, size: CGFloat = 36) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: font(.exo, size: size, weight: .bold), .foregroundColor: UIColor.white, .kern: -0.8
        ])
        if let dot = value.firstIndex(of: ".") {
            let range = NSRange(dot..<value.endIndex, in: value)
            text.addAttribute(.font, value: font(.exo, size: size * 16 / 22, weight: .bold), range: range)
        }
        return text
    }
}
