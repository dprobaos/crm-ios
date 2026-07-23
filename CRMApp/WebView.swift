//  WebView.swift  —  WKWebView do Neuro Voice CRM, "endurecido" para virar app:
//   - JavaScript + cookies/localStorage (mantém a sessão JWT do CRM)
//   - Diálogos JS (alert / confirm / prompt) via WKUIDelegate — o CRM usa
//     confirm()/prompt() (excluir lead, motivo da perda, redefinir senha)
//   - <input type=file> (foto de perfil) usa o seletor nativo do iOS
//   - Links target="_blank" / window.open (ex.: wa.me do WhatsApp) → Safari
//   - Ponte JS→nativo p/ Face ID (window.__NATIVE_APP__ + messageHandlers.bio)
//
//  O CRM é uma SPA (index.html), então NÃO dá pra detectar a "tela de login"
//  pela URL. O disparo do Face ID é feito pelo PRÓPRIO site (index.html chama
//  bio.postMessage({acao:'login'}) quando não há sessão e a biometria está ativa).

import SwiftUI
import WebKit

private let SITE_HOST = "neurovoice.com.br"

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Sinaliza ao site que está rodando dentro do app + registra a ponte.
        let js = "window.__NATIVE_APP__ = true;"
        config.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(context.coordinator, name: "bio")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        // target="_blank"/window.open → carrega na mesma WebView (senão "morre").
        // Exceção: domínio externo (ex.: wa.me) abre no Safari/WhatsApp.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url {
                if let host = u.host, !host.contains(SITE_HOST) {
                    UIApplication.shared.open(u)
                } else {
                    webView.load(URLRequest(url: u))
                }
            }
            return nil
        }

        // Links externos (fora do domínio do site) abrem no Safari / apps nativos.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = navigationAction.request.url, let host = u.host,
               !host.contains(SITE_HOST),
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(u)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        // Página carregou → informa o estado da biometria ao site (controla a UI
        // e o disparo automático do Face ID quando não há sessão).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host?.contains(SITE_HOST) ?? false else { return }
            injetarFlagsBio(webView)
        }

        // Ponte JS→nativo: biometria (Face ID).
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bio" else { return }
            let body = message.body as? [String: Any] ?? [:]
            let acao = body["acao"] as? String ?? ""
            let wv = message.webView
            switch acao {
            case "ativar":
                let payload = body["payload"] as? String ?? ""
                BiometriaManager.shared.ativar(payload: payload) { ok in
                    self.injetarFlagsBio(wv)
                    self.toastWeb(wv, ok ? "Face ID ativado ✓ — use na próxima vez que entrar."
                                          : "Não foi possível ativar o Face ID.")
                }
            case "desativar":
                BiometriaManager.shared.desativar {
                    self.injetarFlagsBio(wv)
                    self.toastWeb(wv, "Login por Face ID desativado.")
                }
            case "login":
                if let wv = wv { BiometriaManager.shared.login(webView: wv) }
            default: break
            }
        }

        // Informa o site se há biometria disponível/ativada (controla a UI).
        private func injetarFlagsBio(_ wv: WKWebView?) {
            let disp = BiometriaManager.shared.disponivel ? "true" : "false"
            let ativ = BiometriaManager.shared.ativado   ? "true" : "false"
            wv?.evaluateJavaScript(
                "window.__BIO_DISPONIVEL__=\(disp);window.__BIO_ATIVADO__=\(ativ);" +
                "if(window.__bioReady)window.__bioReady();", completionHandler: nil)
        }

        private func toastWeb(_ wv: WKWebView?, _ msg: String) {
            let m = msg.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "'", with: "\\'")
            wv?.evaluateJavaScript("(window.toast?window.toast('\(m)'):alert('\(m)'))", completionHandler: nil)
        }

        // ---------- Diálogos JS ----------
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            topVC()?.present(ac, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            topVC()?.present(ac, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            ac.addTextField { $0.text = defaultText }
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(ac.textFields?.first?.text) })
            ac.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            topVC()?.present(ac, animated: true)
        }

        private func topVC() -> UIViewController? {
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.rootViewController
            var top = root
            while let p = top?.presentedViewController { top = p }
            return top
        }
    }
}
