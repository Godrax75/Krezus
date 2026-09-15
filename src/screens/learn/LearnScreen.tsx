import React from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { mockEducationModules } from '../../data/mockData';
import { GlassCard } from '../../components/common/GlassCard';
import { EducationModule } from '../../types';

export const LearnScreen = () => {
  const { colors } = useTheme();
  const { completedModules } = useApp();
  const navigation = useNavigation<any>();

  const totalModules = 12;
  const completedCount = completedModules.length;
  const progress = completedCount / totalModules;

  const getModuleStatus = (module: EducationModule) => {
    if (completedModules.includes(module.id)) return 'completed';
    return module.status;
  };

  const handleModulePress = (module: EducationModule) => {
    const status = getModuleStatus(module);
    if (status === 'locked') return;
    navigation.navigate('ModuleDetail', { moduleId: module.id });
  };

  const renderStatusBadge = (module: EducationModule) => {
    const status = getModuleStatus(module);
    switch (status) {
      case 'completed':
        return (
          <View style={[styles.badge, { backgroundColor: colors.positiveLight }]}>
            <Ionicons name="checkmark-circle" size={16} color={colors.positive} />
            <Text style={[styles.badgeText, { color: colors.positive }]}>Terminé</Text>
          </View>
        );
      case 'available':
        return (
          <View style={[styles.badge, { backgroundColor: colors.primary + '20' }]}>
            <Text style={[styles.badgeText, { color: colors.primary }]}>Disponible</Text>
          </View>
        );
      case 'locked':
        return (
          <View style={[styles.badge, { backgroundColor: colors.surfaceLight }]}>
            <Ionicons name="lock-closed" size={14} color={colors.textTertiary} />
            <Text style={[styles.badgeText, { color: colors.textTertiary }]}>Verrouillé</Text>
          </View>
        );
      default:
        return null;
    }
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={[styles.headerTitle, { color: colors.text }]}>Apprendre</Text>
        </View>

        {/* Progress Section */}
        <View style={styles.progressSection}>
          <Text style={[styles.progressLabel, { color: colors.textSecondary }]}>
            Votre progression
          </Text>
          <View style={[styles.progressBarBg, { backgroundColor: colors.surfaceLight }]}>
            <View
              style={[
                styles.progressBarFill,
                {
                  backgroundColor: colors.primary,
                  width: `${progress * 100}%`,
                },
              ]}
            />
          </View>
          <Text style={[styles.progressText, { color: colors.textSecondary }]}>
            {completedCount}/{totalModules} modules complétés
          </Text>
        </View>

        {/* Module List */}
        {mockEducationModules.map((module, index) => {
          const status = getModuleStatus(module);
          const isLocked = status === 'locked';
          const isCompleted = status === 'completed';

          return (
            <TouchableOpacity
              key={module.id}
              activeOpacity={isLocked ? 1 : 0.7}
              onPress={() => handleModulePress(module)}
              style={[
                styles.moduleCard,
                {
                  backgroundColor: isCompleted
                    ? colors.positiveLight
                    : colors.surface,
                  borderColor: isCompleted ? colors.positive + '30' : colors.border,
                  opacity: isLocked ? 0.5 : 1,
                },
              ]}
            >
              <View
                style={[
                  styles.moduleNumber,
                  {
                    backgroundColor: isCompleted
                      ? colors.positive
                      : isLocked
                      ? colors.textTertiary
                      : colors.primary,
                  },
                ]}
              >
                {isCompleted ? (
                  <Ionicons name="checkmark" size={16} color="#FFFFFF" />
                ) : (
                  <Text style={styles.moduleNumberText}>{index + 1}</Text>
                )}
              </View>
              <View style={styles.moduleContent}>
                <Text
                  style={[
                    styles.moduleTitle,
                    { color: isLocked ? colors.textTertiary : colors.text },
                  ]}
                >
                  {module.title}
                </Text>
                <Text style={[styles.moduleDuration, { color: colors.textTertiary }]}>
                  {module.duration}
                </Text>
              </View>
              {renderStatusBadge(module)}
            </TouchableOpacity>
          );
        })}
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
  header: {
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
  },
  progressSection: {
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.lg,
  },
  progressLabel: {
    fontSize: FontSize.sm,
    marginBottom: Spacing.sm,
  },
  progressBarBg: {
    height: 8,
    borderRadius: 4,
    overflow: 'hidden',
    marginBottom: Spacing.xs,
  },
  progressBarFill: {
    height: '100%',
    borderRadius: 4,
  },
  progressText: {
    fontSize: FontSize.sm,
  },
  moduleCard: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: Spacing.md,
    marginBottom: Spacing.sm,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.lg,
    borderWidth: 1,
  },
  moduleNumber: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: Spacing.sm,
  },
  moduleNumberText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.bold,
    color: '#FFFFFF',
  },
  moduleContent: {
    flex: 1,
  },
  moduleTitle: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
    marginBottom: 2,
  },
  moduleDuration: {
    fontSize: FontSize.xs,
  },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    borderRadius: BorderRadius.full,
  },
  badgeText: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.semibold,
  },
});
