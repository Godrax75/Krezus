import React, { useState, useCallback, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  FlatList,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { mockStocks, mockActivities, generateChartData } from '../../data/mockData';
import { GlassCard } from '../../components/common/GlassCard';
import { AnimatedNumber } from '../../components/common/AnimatedNumber';
import { LineChart } from '../../components/charts/LineChart';
import { TimePeriod, Position } from '../../types';

const PERIODS: TimePeriod[] = ['1J', '1S', '1M', '3M', '6M', '1A', 'Max'];

export const HomeScreen = () => {
  const { colors } = useTheme();
  const { user, portfolio, unreadCount, completedModules } = useApp();
  const navigation = useNavigation<any>();
  const [selectedPeriod, setSelectedPeriod] = useState<TimePeriod>('1M');
  const [refreshing, setRefreshing] = useState(false);

  const chartData = useMemo(() => generateChartData(selectedPeriod), [selectedPeriod]);
  const isPositive = portfolio.totalGain >= 0;

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    setTimeout(() => setRefreshing(false), 1500);
  }, []);

  const getStockForPosition = (position: Position) => {
    return mockStocks[position.stockId.toUpperCase()] ?? null;
  };

  const renderStockCard = ({ item }: { item: Position }) => {
    const stock = getStockForPosition(item);
    if (!stock) return null;
    const dayPositive = stock.dayChange >= 0;

    return (
      <TouchableOpacity
        activeOpacity={0.7}
        onPress={() => navigation.navigate('StockDetail', { stockId: item.stockId })}
        style={styles.stockCardWrapper}
      >
        <GlassCard style={styles.stockCard}>
          <View style={[styles.stockLogo, { backgroundColor: colors.primary }]}>
            <Text style={styles.stockLogoText}>
              {stock.name.charAt(0)}
            </Text>
          </View>
          <Text style={[styles.stockName, { color: colors.text }]} numberOfLines={1}>
            {stock.name}
          </Text>
          <Text style={[styles.stockTicker, { color: colors.textSecondary }]}>
            {stock.ticker}
          </Text>
          <Text style={[styles.stockShares, { color: colors.textTertiary }]}>
            {item.shares} parts
          </Text>
          <Text style={[styles.stockValue, { color: colors.text }]}>
            {item.currentValue.toFixed(2)} €
          </Text>
          <View
            style={[
              styles.changePill,
              { backgroundColor: dayPositive ? colors.positiveLight : colors.negativeLight },
            ]}
          >
            <Text
              style={[
                styles.changeText,
                { color: dayPositive ? colors.positive : colors.negative },
              ]}
            >
              {dayPositive ? '+' : ''}{stock.dayChangePercent.toFixed(2)}%
            </Text>
          </View>
        </GlassCard>
      </TouchableOpacity>
    );
  };

  const recentActivities = mockActivities.slice(-3).reverse();

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
            colors={[colors.primary]}
          />
        }
      >
        {/* Header */}
        <View style={styles.header}>
          <Text style={[styles.greeting, { color: colors.text }]}>
            Bonjour, {user?.firstName || 'Investisseur'}
          </Text>
          <View style={styles.headerIcons}>
            <TouchableOpacity
              onPress={() => navigation.navigate('Notifications')}
              style={styles.iconButton}
            >
              <Ionicons name="notifications-outline" size={24} color={colors.text} />
              {unreadCount > 0 && (
                <View style={[styles.badge, { backgroundColor: colors.notification }]} />
              )}
            </TouchableOpacity>
            <TouchableOpacity
              onPress={() => navigation.navigate('Profile')}
              style={styles.iconButton}
            >
              <Ionicons name="person-circle-outline" size={26} color={colors.text} />
            </TouchableOpacity>
          </View>
        </View>

        {/* Hero Portfolio Card */}
        <GlassCard style={styles.heroCard}>
          <Text style={[styles.portfolioLabel, { color: colors.textSecondary }]}>
            Valeur du portefeuille
          </Text>
          <AnimatedNumber
            value={portfolio.totalValue}
            suffix=" €"
            style={[styles.portfolioValue, { color: colors.text }]}
          />
          <View style={styles.gainRow}>
            <Ionicons
              name={isPositive ? 'arrow-up' : 'arrow-down'}
              size={16}
              color={isPositive ? colors.positive : colors.negative}
            />
            <Text
              style={[
                styles.gainPercent,
                { color: isPositive ? colors.positive : colors.negative },
              ]}
            >
              {isPositive ? '+' : ''}{portfolio.totalGainPercent.toFixed(2)}%
            </Text>
            <Text
              style={[
                styles.gainAmount,
                { color: isPositive ? colors.positive : colors.negative },
              ]}
            >
              {isPositive ? '+' : ''}{portfolio.totalGain.toFixed(2)} €
            </Text>
          </View>

          {/* Period Selector */}
          <View style={styles.periodRow}>
            {PERIODS.map((period) => {
              const active = period === selectedPeriod;
              return (
                <TouchableOpacity
                  key={period}
                  onPress={() => setSelectedPeriod(period)}
                  style={[
                    styles.periodButton,
                    active && { backgroundColor: colors.primary },
                  ]}
                >
                  <Text
                    style={[
                      styles.periodText,
                      { color: active ? colors.background : colors.textTertiary },
                      active && { fontWeight: FontWeight.bold },
                    ]}
                  >
                    {period}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>

          {/* Chart */}
          <LineChart data={chartData} height={200} isPositive={isPositive} />
        </GlassCard>

        {/* Mes Actions */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>Mes Actions</Text>
          <FlatList
            data={portfolio.positions}
            renderItem={renderStockCard}
            keyExtractor={(item) => item.stockId}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.stockListContent}
          />
        </View>

        {/* Activite recente */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>Activité récente</Text>
          {recentActivities.map((activity, index) => (
            <View key={activity.id}>
              <View style={styles.activityItem}>
                <View
                  style={[styles.activityIcon, { backgroundColor: activity.color + '20' }]}
                >
                  <Ionicons
                    name={activity.icon as any}
                    size={18}
                    color={activity.color}
                  />
                </View>
                <View style={styles.activityContent}>
                  <Text style={[styles.activityTitle, { color: colors.text }]}>
                    {activity.title}
                  </Text>
                  <Text style={[styles.activityDesc, { color: colors.textSecondary }]}>
                    {activity.description}
                  </Text>
                </View>
                <Text style={[styles.activityDate, { color: colors.textTertiary }]}>
                  {new Date(activity.date).toLocaleDateString('fr-FR', {
                    day: 'numeric',
                    month: 'short',
                  })}
                </Text>
              </View>
              {index < recentActivities.length - 1 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
            </View>
          ))}
        </View>

        {/* Apprendre */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>Apprendre</Text>
          <TouchableOpacity
            activeOpacity={0.7}
            onPress={() => navigation.navigate('Learn')}
          >
            <GlassCard>
              <View style={styles.learnRow}>
                <Ionicons name="book-outline" size={28} color={colors.primary} />
                <View style={styles.learnContent}>
                  <Text style={[styles.learnQuestion, { color: colors.text }]}>
                    Savez-vous ce qu&apos;est un dividende ?
                  </Text>
                  <View style={styles.progressBarBg}>
                    <View
                      style={[
                        styles.progressBarFill,
                        {
                          backgroundColor: colors.primary,
                          width: `${(completedModules.length / 12) * 100}%`,
                        },
                      ]}
                    />
                  </View>
                  <Text style={[styles.learnProgress, { color: colors.textSecondary }]}>
                    {completedModules.length}/12 modules complétés
                  </Text>
                </View>
              </View>
            </GlassCard>
          </TouchableOpacity>
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
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.sm,
    paddingBottom: Spacing.md,
  },
  greeting: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
  },
  headerIcons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  iconButton: {
    padding: Spacing.xs,
    position: 'relative',
  },
  badge: {
    position: 'absolute',
    top: 4,
    right: 4,
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  heroCard: {
    marginHorizontal: Spacing.md,
    marginBottom: Spacing.lg,
  },
  portfolioLabel: {
    fontSize: FontSize.sm,
    marginBottom: Spacing.xs,
  },
  portfolioValue: {
    fontSize: FontSize.xxxl,
    fontWeight: FontWeight.heavy,
    marginBottom: Spacing.xs,
  },
  gainRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xs,
    marginBottom: Spacing.md,
  },
  gainPercent: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  gainAmount: {
    fontSize: FontSize.md,
  },
  periodRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: Spacing.md,
  },
  periodButton: {
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    borderRadius: BorderRadius.sm,
  },
  periodText: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium,
  },
  section: {
    marginBottom: Spacing.lg,
  },
  sectionTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.sm,
  },
  stockListContent: {
    paddingHorizontal: Spacing.md,
    gap: Spacing.sm,
  },
  stockCardWrapper: {
    width: 160,
  },
  stockCard: {
    alignItems: 'center',
    paddingVertical: Spacing.md,
  },
  stockLogo: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Spacing.sm,
  },
  stockLogoText: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
    color: '#FFFFFF',
  },
  stockName: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
    marginBottom: 2,
    textAlign: 'center',
  },
  stockTicker: {
    fontSize: FontSize.xs,
    marginBottom: Spacing.xs,
  },
  stockShares: {
    fontSize: FontSize.xs,
    marginBottom: Spacing.xs,
  },
  stockValue: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold,
    marginBottom: Spacing.xs,
  },
  changePill: {
    paddingHorizontal: Spacing.sm,
    paddingVertical: 2,
    borderRadius: BorderRadius.full,
  },
  changeText: {
    fontSize: FontSize.xs,
    fontWeight: FontWeight.semibold,
  },
  activityItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
  },
  activityIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: Spacing.sm,
  },
  activityContent: {
    flex: 1,
  },
  activityTitle: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
    marginBottom: 2,
  },
  activityDesc: {
    fontSize: FontSize.sm,
  },
  activityDate: {
    fontSize: FontSize.xs,
    marginLeft: Spacing.sm,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: Spacing.md + 36 + Spacing.sm,
    marginRight: Spacing.md,
  },
  learnRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
  },
  learnContent: {
    flex: 1,
  },
  learnQuestion: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
    marginBottom: Spacing.sm,
  },
  progressBarBg: {
    height: 6,
    borderRadius: 3,
    backgroundColor: 'rgba(255,255,255,0.1)',
    marginBottom: Spacing.xs,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    borderRadius: 3,
  },
  learnProgress: {
    fontSize: FontSize.xs,
  },
});
