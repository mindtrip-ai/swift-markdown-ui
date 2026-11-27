import SwiftUI

extension Sequence where Element == InlineNode {
  func renderText(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    imageBaselineOffsets: [String: CGFloat] = [:],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer,
    placeholderImage: Text?
  ) -> Text {
    var renderer = TextInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      images: images,
      imageBaselineOffsets: imageBaselineOffsets,
      softBreakMode: softBreakMode,
      attributes: attributes,
      placeholderImage: placeholderImage
    )
    renderer.render(self)
    return renderer.result
  }
}

private struct TextInlineRenderer {
  var result = Text("")

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let imageBaselineOffsets: [String: CGFloat]
  private let softBreakMode: SoftBreak.Mode
  private let attributes: AttributeContainer
  private let placeholderImage: Text?
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    imageBaselineOffsets: [String: CGFloat],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer,
    placeholderImage: Text?
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.imageBaselineOffsets = imageBaselineOffsets
    self.softBreakMode = softBreakMode
    self.attributes = attributes
    self.placeholderImage = placeholderImage
  }

  mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines {
      self.render(inline)
    }
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .html(let content):
      self.renderHTML(content)
    case .image(let source, _):
      self.renderImage(source)
    case .link(let destination, let children) where children.isImagesOnly:
      // An attributed string has no room for an image, so a link that wraps only images draws them as images,
      // each carrying the link's destination for a tap handler to find.
      for case .image(let source, _) in children {
        self.renderImage(source, linkDestination: destination)
      }
    default:
      self.defaultRender(inline)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    self.defaultRender(.text(text))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.defaultRender(.softBreak)
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.defaultRender(.lineBreak)
    }
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.defaultRender(.lineBreak)
      self.shouldSkipNextWhitespace = true
    default:
      self.defaultRender(.html(html))
    }
  }

  private mutating func renderImage(_ source: String, linkDestination: String? = nil) {
    var text: Text
    if let image = self.images[source] {
      text = Text(image)
      if let offset = self.imageBaselineOffsets[source] {
        text = text.baselineOffset(offset)
      }
    } else if let placeholderImage {
      text = placeholderImage
    } else {
      return
    }
    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *), let linkDestination {
      text = text.customAttribute(LinkAttribute(urlString: linkDestination))
    }
    self.result = self.result + text
  }

  private mutating func defaultRender(_ inline: InlineNode) {
    var text = Text(
      inline.renderAttributedString(
        baseURL: self.baseURL,
        textStyles: self.textStyles,
        softBreakMode: self.softBreakMode,
        attributes: self.attributes
      )
    )
    if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *), case .link(let destination, _) = inline {
      text = text.customAttribute(LinkAttribute(urlString: destination))
    }

    self.result = self.result + text
  }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct LinkAttribute: TextAttribute {
  public let urlString: String
}

extension Sequence where Element == InlineNode {
  /// Whether every inline is an image, and there is at least one.
  fileprivate var isImagesOnly: Bool {
    var hasImage = false
    for inline in self {
      guard case .image = inline else { return false }
      hasImage = true
    }
    return hasImage
  }
}
