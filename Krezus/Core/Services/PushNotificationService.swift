import Foundation
import Observation
import UserNotifications
import UIKit

/// Notifications push (APNs) : autorisation, jeton d'appareil, réception.
///
/// Le jeton n'est demandé qu'**après** l'accord de l'utilisateur : appeler
/// `registerForRemoteNotifications()` sans autorisation renvoie bien un jeton,
/// mais aucun push ne serait jamais affiché — on stockerait des jetons morts.
///
/// Singleton parce que l'`UIApplicationDelegate` reçoit le jeton hors de toute
/// hiérarchie de vues et n'a donc aucun accès à l'environnement SwiftUI.
@MainActor
@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var deviceToken: String?
    private(set) var lastError: String?

    /// Compte auquel rattacher le jeton ; renseigné à la connexion.
    var userID: UUID? {
        didSet { if userID != nil { persistTokenIfPossible() } }
    }

    var isAuthorized: Bool { status == .authorized || status == .provisional }

    /// L'utilisateur a refusé : seul un aller-retour par Réglages iOS peut
    /// revenir en arrière, l'app ne peut plus redemander.
    var isDenied: Bool { status == .denied }

    private let repository = NotificationsRepository()

    private init() {}

    // MARK: Autorisation

    func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        if isAuthorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Demande l'autorisation puis enregistre l'appareil. Renvoie l'état obtenu.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Ouvre la fiche de l'app dans Réglages iOS — le seul recours après un refus.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Jeton d'appareil

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        lastError = nil
        persistTokenIfPossible()
    }

    func didFailToRegister(error: Error) {
        // Attendu au simulateur sans compte APNs : ce n'est pas une panne à
        // remonter à l'utilisateur, seulement une absence de push.
        lastError = error.localizedDescription
    }

    /// Détache le jeton du compte à la déconnexion, sinon l'appareil
    /// continuerait de recevoir les notifications du compte précédent.
    func unregisterCurrentDevice() async {
        guard AppConfig.isConfigured, let token = deviceToken else { return }
        try? await repository.unregisterDeviceToken(token)
        userID = nil
    }

    private func persistTokenIfPossible() {
        guard AppConfig.isConfigured, let token = deviceToken, let userID else { return }
        Task { try? await repository.registerDeviceToken(token, userID: userID) }
    }

    // MARK: Badge

    /// Aligne la pastille de l'icône sur le nombre de non-lues.
    func setBadge(_ count: Int) {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
}

/// Délégué applicatif minimal : il n'existe que pour capter le jeton APNs et
/// autoriser l'affichage d'une notification quand l'app est au premier plan.
final class KrezusAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushNotificationService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in PushNotificationService.shared.didFailToRegister(error: error) }
    }

    /// Une notification reçue app ouverte reste affichée : les alertes Krezus
    /// (série en danger, ordre exécuté) perdent tout intérêt si elles sont
    /// silencieusement absorbées.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
