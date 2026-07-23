//  BiometriaManager.swift
//  Login por biometria (Face ID / Touch ID) para o Neuro Voice CRM.
//
//  O CRM já entrega no login um JWT de 30 dias (localStorage `nv_t` + `nv_u`).
//  Então guardamos esse "pacote" (JSON {token,user}) no Keychain protegido pela
//  biometria (.biometryCurrentSet, WhenUnlockedThisDeviceOnly) e reinjetamos no
//  site na próxima abertura. NENHUMA mudança no backend PHP é necessária — o app
//  só reidrata a sessão que o próprio site criou.
//   - ativar:    confirma com Face ID → grava o pacote recebido do site.
//   - login:     Face ID libera o pacote → o site repõe a sessão e entra.
//   - desativar: apaga o pacote local.

import Foundation
import LocalAuthentication
import Security
import WebKit

final class BiometriaManager {
    static let shared = BiometriaManager()
    private init() {}

    private let service = "com.dprobaos.crm.biometria"
    private let account = "auth_payload"   // JSON {token,user}

    // Hardware de biometria disponível e configurado?
    var disponivel: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    // Existe um pacote guardado? (checa sem disparar o Face ID)
    var ativado: Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecReturnAttributes as String: true,
        ]
        let st = SecItemCopyMatching(q as CFDictionary, nil)
        // Existe se achou (success) OU se exigiria interação (item protegido presente).
        return st == errSecSuccess || st == errSecInteractionNotAllowed
    }

    // ---- Ativar: confirma biometria e grava o pacote (JSON) vindo do site ----
    func ativar(payload: String, _ done: @escaping (Bool) -> Void) {
        guard !payload.isEmpty else { DispatchQueue.main.async { done(false) }; return }
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Confirme para ativar o login com Face ID") { ok, _ in
            guard ok else { DispatchQueue.main.async { done(false) }; return }
            let saved = self.salvar(payload: payload)
            DispatchQueue.main.async { done(saved) }
        }
    }

    // ---- Login: Face ID libera o pacote → o site repõe a sessão ----
    func login(webView: WKWebView) {
        lerPayloadComBiometria(motivo: "Entrar no CRM com Face ID") { payload in
            guard let payload = payload else { return }
            let safe = payload.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "if(window.__bioPreencherELogar)window.__bioPreencherELogar('\(safe)')",
                completionHandler: nil)
        }
    }

    // ---- Desativar: apaga o pacote local ----
    func desativar(_ done: @escaping () -> Void) {
        apagarPayload()
        DispatchQueue.main.async { done() }
    }

    // ================= Keychain =================
    @discardableResult
    private func salvar(payload: String) -> Bool {
        apagarPayload()
        guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil),
              let data = payload.data(using: .utf8) else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func apagarPayload() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }

    private func lerPayloadComBiometria(motivo: String, _ done: @escaping (String?) -> Void) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseOperationPrompt as String: motivo,
            kSecReturnData as String: true,
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            var item: CFTypeRef?
            let st = SecItemCopyMatching(q as CFDictionary, &item)
            let payload = (st == errSecSuccess) ? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
            DispatchQueue.main.async { done(payload) }
        }
    }
}
