//
//  ContentSwipeBack.swift
//  Sliding
//

import SwiftUI

extension View {
    /// Turns iOS's swipe-anywhere-to-go-back off while `disabled` is true, so a sideways drag
    /// on the screen's content can be used for something else. Swiping from the screen's
    /// edge still goes back.
    func contentSwipeBackDisabled(_ disabled: Bool) -> some View {
        background(ContentSwipeBack(disabled: disabled).frame(width: 0, height: 0))
    }
}

private struct ContentSwipeBack: UIViewControllerRepresentable {
    let disabled: Bool

    final class Controller: UIViewController {
        var disabled = false { didSet { apply() } }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Leaving: give the next screen its swipe back.
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true
        }

        private func apply() {
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = !disabled
        }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.disabled = disabled
    }
}
