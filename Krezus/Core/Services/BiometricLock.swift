import Foundation
import Observation
import LocalAuthentication

/// Verrou biométrique à l'ouverture de l'app.
///
/// Krezus ne manipule aucun argent réel, mais le portefeuille, la progression
/// et les conversations avec Hercule sont des données personnelles : le verrou
/// est proposé, jamais imposé.
///
/// Le repli sur le code de l'appareil (`deviceOwnerAuthentication` plutôt que
/// `…WithBiometrics`) est délibéré — sans lui, un échec de Face ID enfermerait
/// l'utilisateur hors de ses propres données.
@MainActor
@Observable
final class BiometricLock {

    /// Vrai quand l'app doit être déverrouillée avant d'afficher son contenu.
    private(set) var isLocked = false
    private(set) var lastError: String?

    /// Une évaluation est déjà en cours — évite d'empiler deux invites système
    /// quand la scène repasse active pendant que l'alerte est affichée.
    private var isEvaluating = false

    /// Type de biométrie disponible sur l'appareil, pour libeller le réglage.
    var biometryLabel: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return t("security.device_passcode")
        }
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return t("security.device_passcode")
        }
    }

    /// Faux sur un appareil sans code configuré : proposer le réglage y serait
    /// un bouton mort.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Verrouille au retour de l'arrière-plan si le réglage est actif.
    func lockIfNeeded(enabled: Bool) {
        guard enabled, isAvailable else { return }
        isLocked = true
    }

    func unlockWithoutPrompt() {
        isLocked = false
    }

    /// Présente l'invite système. Ne déverrouille qu'en cas de succès.
    func authenticate() async {
        guard isLocked, !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let context = LAContext()
        context.localizedCancelTitle = t("common.cancel")
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: t("lock.reason"))
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = (error as? LAError)?.code == .userCancel
                ? nil
                : error.localizedDescription
        }
    }
}
