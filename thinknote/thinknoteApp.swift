//
//  thinknoteApp.swift
//  thinknote
//
//  Created by 严汀 on 4/5/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct thinknoteApp: App {
    init() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            Self.prewarmKeyboard()
        }
    }

    var body: some Scene {
        WindowGroup {
            if isRunningInPreviews {
                ContentView(viewModel: .previewModel(), shouldBootstrap: false)
            } else {
                ContentView()
            }
        }
        .modelContainer(ThinknotePersistence.sharedContainer)
    }

    @MainActor
    private static func prewarmKeyboard() {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        let dummy = UITextField()
        window.addSubview(dummy)
        dummy.becomeFirstResponder()
        dummy.resignFirstResponder()
        dummy.removeFromSuperview()
    }
}
