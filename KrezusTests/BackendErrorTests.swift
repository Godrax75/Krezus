import Testing
import Foundation
@testable import Krezus

/// Mapping de la classe SQLSTATE privée « KR » vers `KrezusError`.
///
/// L'enjeu n'est pas cosmétique. Les migrations lèvent leurs exceptions avec un
/// message **rédigé en français en dur** (`raise exception 'Leçon introuvable'`).
/// Un code non mappé tombe dans `.server(message)` et affiche donc ce français
/// à un utilisateur anglophone. Ce test est la barrière : ajouter un
/// `using errcode = 'KR…'` dans une migration sans l'ajouter côté Swift le fait
/// tomber ici plutôt que devant l'utilisateur.
@MainActor
struct BackendErrorTests {

    /// Tous les codes levés par les migrations 0002 à 0008, relevés à la main
    /// depuis les fichiers SQL — la liste doit rester exhaustive.
    private static let allCodes = [
        "KR001", "KR002", "KR003", "KR004", "KR010",   // moteur d'ordres  (0002)
        "KR020", "KR021", "KR022",                      // academy          (0005)
        "KR030",                                        // oracle           (0006)
        "KR040", "KR041", "KR042", "KR043", "KR044",   // arena            (0007)
        "KR050", "KR051", "KR052",                      // hercule          (0008)
    ]

    @Test("Chaque code SQLSTATE connu donne une erreur typée, jamais le message SQL")
    func everyKnownCodeIsTyped() {
        for code in Self.allCodes {
            let error = KrezusError.from(sqlState: code, message: "message SQL brut")
            if case .server = error {
                Issue.record("\(code) n'est pas mappé : le message PL/pgSQL remonterait tel quel")
            }
        }
    }

    @Test("Un code inconnu retombe sur le message du serveur plutôt que de se taire")
    func unknownCodeFallsBackToServerMessage() {
        let error = KrezusError.from(sqlState: "KR999", message: "quelque chose d'inattendu")
        guard case .server(let message) = error else {
            Issue.record("Un code inconnu doit rester un .server(message)")
            return
        }
        #expect(message == "quelque chose d'inattendu")
    }

    @Test("Chaque erreur typée est traduite dans les deux langues",
          arguments: ["fr", "en"])
    func everyTypedErrorIsLocalized(_ code: String) throws {
        let language = try #require(AppLanguage(rawValue: code))
        L10n.use(language)
        defer { L10n.use(.fr) }

        for code in Self.allCodes {
            let description = KrezusError.from(sqlState: code, message: "").errorDescription
            let text = try #require(description, "\(code) n'a aucun libellé")
            #expect(!text.isEmpty, "\(code) rend un libellé vide en \(language.rawValue)")
        }
    }
}
