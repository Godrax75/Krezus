import React from 'react';
import { View, Text, ScrollView, StyleSheet, TouchableOpacity } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { useTheme, Spacing, FontSize, FontWeight } from '../../theme';
import { LEGAL_DOCUMENTS, LegalDocumentId } from '../../data/legalContent';

type LegalParams = {
  Legal: { document: LegalDocumentId };
};

export const LegalScreen = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const route = useRoute<RouteProp<LegalParams, 'Legal'>>();
  const doc = LEGAL_DOCUMENTS[route.params.document];

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={[styles.headerTitle, { color: colors.text }]} numberOfLines={1}>
          {doc.title}
        </Text>
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
      >
        <Text style={[styles.updatedAt, { color: colors.textTertiary }]}>
          Dernière mise à jour : {doc.updatedAt}
        </Text>

        {doc.sections.map((section) => (
          <View key={section.heading} style={styles.section}>
            <Text style={[styles.heading, { color: colors.primary }]}>
              {section.heading}
            </Text>
            <Text style={[styles.body, { color: colors.textSecondary }]}>
              {section.body}
            </Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
  },
  backButton: {
    padding: Spacing.xs,
    marginRight: Spacing.sm,
  },
  headerTitle: {
    flex: 1,
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
  },
  scrollContent: {
    paddingHorizontal: Spacing.md,
    paddingBottom: Spacing.xxl,
  },
  updatedAt: {
    fontSize: FontSize.xs,
    marginBottom: Spacing.lg,
  },
  section: {
    marginBottom: Spacing.lg,
  },
  heading: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
    marginBottom: Spacing.xs,
  },
  body: {
    fontSize: FontSize.md,
    lineHeight: 23,
  },
});
