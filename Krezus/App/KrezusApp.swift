import SwiftUI

@main
struct KrezusApp: App {
    /// Le délégué n'existe que pour capter le jeton APNs : SwiftUI seul n'a pas
    /// de point d'entrée pour `didRegisterForRemoteNotifications`.
    @UIApplicationDelegateAdaptor(KrezusAppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var settings = SettingsStore()
    @State private var auth = AuthService()
    @State private var profile = ProfileStore()
    @State private var store = TradingStore()
    @State private var learning = LearningStore()
    @State private var arena = ArenaStore()
    @State private var hercule = HerculeStore()
    @State private var subscriptions = SubscriptionService()
    @State private var oracle = OracleStore()
    @State private var notifications = NotificationStore()
    @State private var push = PushNotificationService.shared
    @State private var lock = BiometricLock()
    @State private var router = Router()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environment(appState)
                .environment(settings)
                .environment(auth)
                .environment(profile)
                .environment(store)
                .environment(learning)
                .environment(arena)
                .environment(hercule)
                .environment(subscriptions)
                .environment(oracle)
                .environment(notifications)
                .environment(push)
                .environment(lock)
                .environment(router)
                .environment(\.locale, settings.language.locale)
                .modifier(RebuildOnLanguageOrTextSize(language: settings.language))
                .preferredColorScheme(settings.appearance.colorScheme)
                .task { await auth.restore() }
                .task { await auth.observe() }
                .task { await push.refreshStatus() }
                .onOpenURL { url in
                    Task { await auth.handleOAuthCallback(url) }
                }
                // Le compte n'est connu qu'après restauration de la session :
                // c'est à ce moment, et pas au lancement, qu'on rattache les
                // préférences, le jeton de push et la boîte de notifications.
                .onChange(of: auth.userID, initial: true) { _, userID in
                    settings.userID = userID
                    push.userID = userID
                    Task {
                        await profile.load(userID: userID)
                        await notifications.load(userID: userID)
                        // Les stores basculent sur le serveur ici, et seulement
                        // ici : sans compte, ou sans secrets, ils restent en
                        // démo — mêmes écrans, données locales.
                        if let userID {
                            await store.connect(userID: userID)
                            await learning.connect(userID: userID)
                        } else {
                            store.disconnect()
                            learning.disconnect()
                        }
                    }
                }
                // Les contenus éditoriaux (leçons, rangs, scénarios) sont des
                // ressources embarquées, pas des chaînes du catalogue : c'est
                // aux stores de les relire quand la langue change.
                .onChange(of: settings.language) { _, _ in
                    learning.loadContent()
                    oracle.loadContent()
                }
                .onChange(of: notifications.unreadCount, initial: true) { _, count in
                    push.setBadge(count)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Verrouiller au passage en arrière-plan, pas au retour :
                    // l'aperçu du multitâche est capturé à cet instant précis,
                    // et il ne doit pas montrer le portefeuille.
                    if phase == .background { lock.lockIfNeeded(enabled: settings.biometricLock) }
                }
        }
    }
}

/// Reconstruit l'arbre de vues quand la langue ou la taille de texte système
/// change.
///
/// Les deux réglages sont lus en dehors du système d'invalidation de SwiftUI :
/// les chaînes passent par `L10n` et les tailles par `UIFontMetrics`, ni l'un
/// ni l'autre n'étant une dépendance observée. Sans cette clé, basculer en
/// anglais ou agrandir le texte dans Réglages ne redessinerait rien avant le
/// prochain lancement. Le coût est une reconstruction complète — mais elle ne
/// survient que sur une action délibérée de l'utilisateur, jamais en usage
/// courant.
private struct RebuildOnLanguageOrTextSize: ViewModifier {
    let language: AppLanguage
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.id("\(language.rawValue)-\(typeSize)")
    }
}

/// Aiguillage racine :
/// - onboarding pas encore vu → présentation en trois étapes ;
/// - app non configurée (pas de secrets Supabase) → shell en mode démo ;
/// - configurée mais non connectée → écran de connexion ;
/// - connectée → app complète branchée sur les données.
///
/// Le verrou biométrique se pose **au-dessus** de tout : il protège aussi le
/// mode démo, dont le portefeuille est tout aussi personnel.
struct AuthGate: View {
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if !settings.hasSeenOnboarding {
                OnboardingScreen()
            } else if !AppConfig.isConfigured {
                RootView()                     // mode démo : TradingStore en mémoire
            } else if auth.isSignedIn {
                RootView()
            } else {
                SignInScreen()
            }
        }
        .modifier(BiometricLockGate())
    }
}

/// Recouvre l'app tant que le déverrouillage n'a pas eu lieu.
private struct BiometricLockGate: ViewModifier {
    @Environment(BiometricLock.self) private var lock

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.isLocked {
                    lockScreen
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: lock.isLocked)
    }

    private var lockScreen: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            VStack(spacing: KrezusSpacing.s4) {
                Image("krezus-mascot").resizable().scaledToFit().frame(width: 64, height: 64)
                Text(t("lock.title"))
                    .font(KrezusFont.display(19, .heavy)).foregroundStyle(KrezusColor.ink)

                if let error = lock.lastError {
                    Text(error)
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, KrezusSpacing.s6)
                }

                Button {
                    Task { await lock.authenticate() }
                } label: {
                    Text(t("lock.unlock_with", lock.biometryLabel))
                        .font(KrezusFont.display(15, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, KrezusSpacing.s5)
                        .padding(.vertical, 13)
                        .background(KrezusColor.brandFill)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .task { await lock.authenticate() }
    }
}
