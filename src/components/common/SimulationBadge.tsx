import React from 'react';
import { View, Text, StyleSheet, StyleProp, ViewStyle } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';

interface SimulationBadgeProps {
  /** Texte alternatif ; par défaut « Portefeuille simulé ». */
  label?: string;
  style?: StyleProp<ViewStyle>;
}

/**
 * Pastille qui rappelle que le portefeuille n'engage pas d'argent réel.
 *
 * Ce n'est pas un ornement : présenter un portefeuille fictif comme réel
 * tombe sous la règle 2.3.1 de l'App Store (fonctionnalités trompeuses), et
 * c'est de toute façon la première chose qu'un débutant doit comprendre.
 */
export const SimulationBadge = ({
  label = 'Portefeuille simulé',
  style,
}: SimulationBadgeProps) => {
  const { colors } = useTheme();

  return (
    <View
      style={[
        styles.badge,
        { backgroundColor: colors.glass, borderColor: colors.glassBorder },
        style,
      ]}
    >
      <Ionicons name="school-outline" size={12} color={colors.primary} />
      <Text style={[styles.label, { color: colors.primary }]}>{label}</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    gap: Spacing.xs,
    paddingHorizontal: Spacing.sm,
    paddingVertical: 3,
    borderRadius: BorderRadius.full,
    borderWidth: StyleSheet.hairlineWidth,
  },
  label: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.semibold,
  },
});
