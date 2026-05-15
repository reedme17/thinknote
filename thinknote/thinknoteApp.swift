//
//  thinknoteApp.swift
//  thinknote
//
//  Created by 严汀 on 4/5/26.
//

import SwiftUI
import SwiftData

@main
struct thinknoteApp: App {
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
}
