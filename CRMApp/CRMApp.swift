//  CRMApp.swift  —  App "casca" do Neuro Voice CRM (WebView + Face ID)
//  Target único (iOS 15+). Espelha o painel web em produção.

import SwiftUI

@main
struct CRMApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: "https://neurovoice.com.br/crm/")!)
                .ignoresSafeArea()
        }
    }
}
