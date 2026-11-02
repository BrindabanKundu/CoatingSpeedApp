//
//  CoatingSpeedAppApp.swift
//  CoatingSpeedApp
//
//  Created by Brindaban Kundu on 14.09.2026.
//

import SwiftUI

@main
struct CoatingSpeedAppApp: App {

    @State private var showWelcome = true

    var body: some Scene {

        WindowGroup {

            if showWelcome {

                AboutView {

                    showWelcome = false
                }

            } else {

                ContentView()
            }
        }
    }
}
