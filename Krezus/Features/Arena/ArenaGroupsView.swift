import SwiftUI

/// Groupes privés — se rejoignent par code, jamais en parcourant une liste
/// publique. Un groupe de classe ou d'amis n'a pas à être découvrable.
struct ArenaGroupsView: View {
    @Environment(ArenaStore.self) private var arena
    @Environment(Router.self) private var router

    @State private var joinCode = ""
    @State private var newGroupName = ""
    @State private var showCreate = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            joinCard
            if !arena.groups.isEmpty { myGroupsCard }
        }
    }

    private var joinCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("arena.join.title"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                Text(t("arena.join.subtitle"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)

                HStack(spacing: 8) {
                    TextField("KRZ26A", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(KrezusFont.display(15, .bold))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(KrezusColor.tint)
                        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))

                    Button {
                        join()
                    } label: {
                        Text(t("arena.join.cta"))
                            .font(KrezusFont.body(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(KrezusColor.brandFill)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .opacity(joinCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let error {
                    Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                }

                Divider().overlay(KrezusColor.divider).padding(.vertical, 2)

                if showCreate {
                    HStack(spacing: 8) {
                        TextField(t("arena.group_name_placeholder"), text: $newGroupName)
                            .font(KrezusFont.bodyMd)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(KrezusColor.tint)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))

                        Button { create() } label: {
                            Text(t("common.create"))
                                .font(KrezusFont.body(13, .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .background(KrezusColor.brandFill)
                                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { showCreate = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text(t("arena.create_group"))
                        }
                        .font(KrezusFont.body(12.5, .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var myGroupsCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("arena.my_groups"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    .padding(.bottom, 6)

                ForEach(Array(arena.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().overlay(KrezusColor.divider) }
                    groupRow(group)
                }
            }
        }
    }

    private func groupRow(_ group: ArenaGroup) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14)).foregroundStyle(KrezusColor.brandText)
                .frame(width: 32, height: 32)
                .background(KrezusColor.tintStrong).clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
                Text(t("arena.group_code", group.inviteCode))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }

            Spacer(minLength: 0)

            Button {
                arena.selectedGroup = group
                router.showToast(t("arena.toast.filtered", group.name))
            } label: {
                Text(t("arena.tab.leaderboard"))
                    .font(KrezusFont.body(12, .semibold)).foregroundStyle(KrezusColor.brandText)
            }
            .buttonStyle(.plain)

            Menu {
                Button(t("arena.leave_group"), role: .destructive) {
                    arena.leaveGroup(group)
                    router.showToast(t("arena.toast.group_left"))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KrezusColor.fg4)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 9)
    }

    private func join() {
        error = nil
        Task {
            do {
                let group = try await arena.joinGroup(code: joinCode)
                joinCode = ""
                router.showToast(t("arena.toast.joined", group.name))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func create() {
        error = nil
        Task {
            do {
                let group = try await arena.createGroup(named: newGroupName)
                newGroupName = ""
                showCreate = false
                router.showToast(t("arena.toast.group_created", group.inviteCode))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
