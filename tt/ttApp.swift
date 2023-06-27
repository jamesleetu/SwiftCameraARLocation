//
//  ttApp.swift
//  tt
//
//  Created by 이태웅 on 2023/06/27.
//

import SwiftUI

@main
struct ttApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
