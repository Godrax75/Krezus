import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Switch,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import * as Linking from 'expo-linking';
import * as Haptics from 'expo-haptics';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { COMPANY, isConfigured } from '../../data/legalContent';

type ThemeMode = 'dark' | 'light' | 'auto';

const MODE_LABELS: Record<ThemeMode, string> = {
  dark: 'Sombre',
  light: 'Clair',
  auto: 'Auto',
};

const MODE_CYCLE: ThemeMode[] = ['dark', 'light', 'auto'];

export const ProfileScreen = () => {
  const { colors, mode, setMode } = useTheme();
  const { user, giftReveal, logout, deleteAccount } = useApp();
  const navigation = useNavigation<any>();
  const [biometricEnabled, setBiometricEnabled] = useState(false);

  const supportConfigured = isConfigured(COMPANY.supportEmail);

  const confirmDeleteAccount = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    Alert.alert(
      'Supprimer mon compte',
      'Votre profil, votre progression et votre coffret activé seront définitivement effacés de cet appareil. Cette action est irréversible.',
      [
        { text: 'Annuler', style: 'cancel' },
        {
          text: 'Supprimer',
          style: 'destructive',
          onPress: async () => {
            await deleteAccount();
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          },
        },
      ]
    );
  };

  const cycleMode = () => {
    const currentIndex = MODE_CYCLE.indexOf(mode as ThemeMode);
    const nextIndex = (currentIndex + 1) % MODE_CYCLE.length;
    setMode(MODE_CYCLE[nextIndex]);
  };

  const renderRow = (
    label: string,
    options?: {
      rightText?: string;
      onPress?: () => void;
      switchValue?: boolean;
      onSwitchChange?: (value: boolean) => void;
      showChevron?: boolean;
    }
  ) => {
    const { rightText, onPress, switchValue, onSwitchChange, showChevron = true } =
      options || {};

    const content = (
      <View style={[styles.row, { borderBottomColor: colors.border }]}>
        <Text style={[styles.rowLabel, { color: colors.text }]}>{label}</Text>
        <View style={styles.rowRight}>
          {rightText && (
            <Text style={[styles.rowRightText, { color: colors.textTertiary }]}>
              {rightText}
            </Text>
          )}
          {onSwitchChange !== undefined && switchValue !== undefined ? (
            <Switch
              value={switchValue}
              onValueChange={onSwitchChange}
              trackColor={{ false: colors.surfaceLight, true: colors.primary }}
              thumbColor="#FFFFFF"
            />
          ) : showChevron ? (
            <Ionicons name="chevron-forward" size={18} color={colors.textTertiary} />
          ) : null}
        </View>
      </View>
    );

    if (onPress) {
      return (
        <TouchableOpacity key={label} activeOpacity={0.7} onPress={onPress}>
          {content}
        </TouchableOpacity>
      );
    }

    return <View key={label}>{content}</View>;
  };

  const initials = user
    ? user.firstName.charAt(0).toUpperCase()
    : 'K';

  const activationDate = user?.activationDate
    ? new Date(user.activationDate).toLocaleDateString('fr-FR', {
        day: 'numeric',
        month: 'long',
        year: 'numeric',
      })
    : '14 février 2026';

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Profile Section */}
        <View style={styles.profileSection}>
          <View style={[styles.avatar, { borderColor: colors.primary }]}>
            <Text style={[styles.avatarText, { color: colors.primary }]}>{initials}</Text>
          </View>
          <Text style={[styles.userName, { color: colors.text }]}>
            {user ? `${user.firstName}` : 'Investisseur'}
          </Text>
          {user?.email && (
            <Text style={[styles.userEmail, { color: colors.textSecondary }]}>
              {user.email}
            </Text>
          )}
          <Text style={[styles.activationText, { color: colors.textTertiary }]}>
            Coffret activé le {activationDate}
          </Text>
          {giftReveal?.giftedBy && (
            <Text style={[styles.giftedByText, { color: colors.primary }]}>
              Offert par {giftReveal.giftedBy}
            </Text>
          )}
        </View>

        {/* Parametres */}
        <View style={styles.sectionContainer}>
          <Text style={[styles.sectionTitle, { color: colors.primary }]}>Paramètres</Text>
          {renderRow('Notifications')}
          {renderRow('Apparence', {
            rightText: MODE_LABELS[mode as ThemeMode] || 'Sombre',
            onPress: cycleMode,
          })}
          {renderRow('Langue', { rightText: 'Français' })}
          {renderRow('Face ID / Touch ID', {
            switchValue: biometricEnabled,
            onSwitchChange: setBiometricEnabled,
            showChevron: false,
          })}
          {renderRow('Changer le mot de passe')}
        </View>

        {/* Legal */}
        <View style={styles.sectionContainer}>
          <Text style={[styles.sectionTitle, { color: colors.primary }]}>Légal</Text>
          {renderRow('CGU', {
            onPress: () => navigation.navigate('Legal', { document: 'cgu' }),
          })}
          {renderRow('Politique de confidentialité', {
            onPress: () => navigation.navigate('Legal', { document: 'privacy' }),
          })}
          {renderRow('Mentions légales', {
            onPress: () => navigation.navigate('Legal', { document: 'notices' }),
          })}
        </View>

        {/* Support */}
        <View style={styles.sectionContainer}>
          <Text style={[styles.sectionTitle, { color: colors.primary }]}>Support</Text>
          {renderRow('FAQ')}
          {/* Activé dès que l'adresse de contact est renseignée dans legalContent.ts */}
          {renderRow('Contacter le support', {
            onPress: supportConfigured
              ? () => Linking.openURL(`mailto:${COMPANY.supportEmail}?subject=Support%20Krezus`)
              : undefined,
          })}
        </View>

        {/* Compte */}
        <View style={styles.sectionContainer}>
          <Text style={[styles.sectionTitle, { color: colors.primary }]}>Compte</Text>
          <TouchableOpacity activeOpacity={0.7} onPress={confirmDeleteAccount}>
            <View style={[styles.row, { borderBottomColor: colors.border }]}>
              <Text style={[styles.rowLabel, { color: colors.negative }]}>
                Supprimer mon compte
              </Text>
              <Ionicons name="trash-outline" size={18} color={colors.negative} />
            </View>
          </TouchableOpacity>
          <Text style={[styles.dangerHint, { color: colors.textTertiary }]}>
            Efface définitivement votre profil, votre progression et votre coffret activé
            de cet appareil.
          </Text>
        </View>

        {/* Footer */}
        <View style={styles.footer}>
          <TouchableOpacity onPress={logout} style={styles.logoutButton}>
            <Text style={[styles.logoutText, { color: colors.negative }]}>
              Se déconnecter
            </Text>
          </TouchableOpacity>
          <Text style={[styles.versionText, { color: colors.textTertiary }]}>
            Krezus v1.0.0
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: Spacing.xxl,
  },
  profileSection: {
    alignItems: 'center',
    paddingVertical: Spacing.xl,
    paddingHorizontal: Spacing.md,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Spacing.md,
  },
  avatarText: {
    fontSize: FontSize.xxxl,
    fontWeight: FontWeight.bold,
  },
  userName: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
    marginBottom: Spacing.xs,
  },
  userEmail: {
    fontSize: FontSize.md,
    marginBottom: Spacing.sm,
  },
  activationText: {
    fontSize: FontSize.sm,
    marginBottom: Spacing.xs,
  },
  giftedByText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
  },
  sectionContainer: {
    marginBottom: Spacing.lg,
  },
  sectionTitle: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.bold,
    textTransform: 'uppercase',
    letterSpacing: 1,
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.sm,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  rowLabel: {
    fontSize: FontSize.md,
    flex: 1,
  },
  rowRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  rowRightText: {
    fontSize: FontSize.sm,
  },
  dangerHint: {
    fontSize: FontSize.xs,
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.sm,
    lineHeight: 16,
  },
  footer: {
    alignItems: 'center',
    paddingVertical: Spacing.xl,
    gap: Spacing.md,
  },
  logoutButton: {
    paddingVertical: Spacing.sm,
    paddingHorizontal: Spacing.lg,
  },
  logoutText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  versionText: {
    fontSize: FontSize.xs,
  },
});
