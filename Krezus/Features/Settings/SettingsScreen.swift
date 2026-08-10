import SwiftUI

/// « Apparence et langue ».
///
/// Le changement de langue s'applique immédiatement, sans redémarrage : la
/// racine des vues est reconstruite via son `id` (voir `KrezusApp`). Les
/// contenus éditoriaux (leçons, fiches action) restent en français tant que
/// leur traduction n'est pas rédigée — l'écran le dit plutôt que de le laisser
/// découvrir.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var settings = settings

        return ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    KrzGroupLabel(text: t("settings.appearance"))
                    KrzCard {
                        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                            KrzSegmented(
                                options: KrezusAppearance.allCases.map { ($0, $0.label) },
                                selection: $settings.appearance)
                            Text(t("settings.appearance_note"))
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    KrzGroupLabel(text: t("settings.language"))
                    KrzCard {
                        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                            KrzSegmented(
                                options: AppLanguage.allCases.map { ($0, $0.label) },
                                selection: $settings.language)
                            Text(t("settings.language_note"))
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    KrzGroupLabel(text: t("settings.discovery"))
                    KrzSettingsGroup {
                        KrzSettingsRow(icon: "sparkles.rectangle.stack",
                                       title: t("settings.replay_onboarding"),
                                       subtitle: t("settings.replay_onboarding_detail")) {
                            settings.replayOnboarding()
                            router.showToast(t("settings.replay_toast"))
                        }
                    }

                    KrzPaperMoneyNote().padding(.top, KrezusSpacing.s4)
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.row.appearance"))
    }
}
