//
//  easy_webuiApp.swift
//  easy-webui
//
//  Created by lihangyu on 2026/8/14.
//

import SwiftUI

@main
struct easy_webuiApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 600)
    }
}
