import React from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { Notification } from '../../types';

const getIconForType = (type: Notification['type']): { name: string; color: string } => {
  switch (type) {
    case 'price_move':
      return { name: 'trending-up', color: '#4CAF50' };
    case 'dividend':
      return { name: 'cash-outline', color: '#FF9800' };
    case 'education':
      return { name: 'book-outline', color: '#2196F3' };
    case 'anniversary':
      return { name: 'gift-outline', color: '#C9A84C' };
    case 'news':
      return { name: 'newspaper-outline', color: '#9C27B0' };
    default:
      return { name: 'notifications-outline', color: '#9E9E9E' };
  }
};

const getRelativeTime = (dateStr: string): string => {
  const now = new Date();
  const date = new Date(dateStr);
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMin / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMin < 1) return "À l'instant";
  if (diffMin < 60) return `Il y a ${diffMin} min`;
  if (diffHours < 24) return `Il y a ${diffHours}h`;
  if (diffDays < 7) return `Il y a ${diffDays}j`;
  return date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
};

export const NotificationsScreen = () => {
  const { colors } = useTheme();
  const { notifications, markNotificationRead, deleteNotification } = useApp();

  const renderItem = ({ item }: { item: Notification }) => {
    const icon = getIconForType(item.type);
    const isUnread = !item.read;

    return (
      <View
        style={[
          styles.notificationItem,
          isUnread && { borderLeftColor: colors.primary, borderLeftWidth: 3 },
          { backgroundColor: isUnread ? colors.surfaceLight : 'transparent' },
        ]}
      >
        <View style={[styles.iconCircle, { backgroundColor: icon.color + '20' }]}>
          <Ionicons name={icon.name as any} size={20} color={icon.color} />
        </View>
        <View style={styles.contentWrapper}>
          <Text style={[styles.title, { color: colors.text }]}>{item.title}</Text>
          <Text
            style={[styles.description, { color: colors.textSecondary }]}
            numberOfLines={2}
          >
            {item.description}
          </Text>
          <Text style={[styles.time, { color: colors.textTertiary }]}>
            {getRelativeTime(item.date)}
          </Text>
        </View>
        <View style={styles.actions}>
          {isUnread && (
            <TouchableOpacity
              onPress={() => markNotificationRead(item.id)}
              style={[styles.actionButton, { backgroundColor: colors.primary + '20' }]}
            >
              <Ionicons name="checkmark" size={16} color={colors.primary} />
            </TouchableOpacity>
          )}
          <TouchableOpacity
            onPress={() => deleteNotification(item.id)}
            style={[styles.actionButton, { backgroundColor: colors.negativeLight }]}
          >
            <Ionicons name="close" size={16} color={colors.negative} />
          </TouchableOpacity>
        </View>
      </View>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <Ionicons name="notifications-off-outline" size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyText, { color: colors.textSecondary }]}>
        Aucune notification
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.header}>
        <Text style={[styles.headerTitle, { color: colors.text }]}>Notifications</Text>
      </View>
      <FlatList
        data={notifications}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={
          notifications.length === 0 ? styles.emptyList : styles.listContent
        }
        ListEmptyComponent={renderEmpty}
        showsVerticalScrollIndicator={false}
        ItemSeparatorComponent={() => (
          <View style={[styles.separator, { backgroundColor: colors.border }]} />
        )}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
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
  listContent: {
    paddingBottom: Spacing.xxl,
  },
  emptyList: {
    flex: 1,
  },
  notificationItem: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
  },
  iconCircle: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: Spacing.sm,
  },
  contentWrapper: {
    flex: 1,
    marginRight: Spacing.sm,
  },
  title: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
    marginBottom: 2,
  },
  description: {
    fontSize: FontSize.sm,
    lineHeight: 18,
    marginBottom: 4,
  },
  time: {
    fontSize: FontSize.xs,
  },
  actions: {
    flexDirection: 'column',
    gap: Spacing.xs,
    alignItems: 'center',
  },
  actionButton: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: Spacing.md + 40 + Spacing.sm,
    marginRight: Spacing.md,
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.md,
  },
  emptyText: {
    fontSize: FontSize.lg,
  },
});
