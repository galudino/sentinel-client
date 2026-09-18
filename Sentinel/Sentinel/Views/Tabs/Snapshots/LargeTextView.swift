//
//  LargeTextView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - LargeTextView

/// A `UITextView` wrapper for efficiently displaying very large export previews
/// (100K+ characters). Unlike SwiftUI `Text`, it renders lazily and scrolls
/// horizontally without wrapping, keeping wide CSV/JSON previews readable.
struct LargeTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .systemBackground
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .secondaryLabel
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = true

        // Don't wrap — allow horizontal scrolling for wide rows.
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return textView
    }

    func updateUIView(_ textView: UITextView, context _: Context) {
        if textView.text != text {
            textView.text = text
            textView.setContentOffset(.zero, animated: false)
        }
    }
}
