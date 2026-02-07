import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { mockStocks, mockNews, generateStockChartData } from '../../data/mockData';
import { GlassCard } from '../../components/common/GlassCard';
import { LineChart } from '../../components/charts/LineChart';
import { TimePeriod } from '../../types';

const PERIODS: TimePeriod[] = ['1J', '1S', '1M', '3M', '6M', '1A', 'Max'];

type StockDetailParams = {
  StockDetail: { stockId: string };
};

export const StockDetailScreen = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const route = useRoute<RouteProp<StockDetailParams, 'StockDetail'>>();
  const { portfolio } = useApp();
  const { stockId } = route.params;

  const stock = mockStocks[stockId.toUpperCase()];
  const position = portfolio.positions.find(
    (p) => p.stockId.toLowerCase() === stockId.toLowerCase()
  );

  const [selectedPeriod, setSelectedPeriod] = useState<TimePeriod>('1M');

  const chartData = useMemo(
    () => (stock ? generateStockChartData(selectedPeriod, stock.currentPrice) : []),
    [selectedPeriod, stock]
  );

  const isPositive = stock ? stock.dayChange >= 0 : true;
  const positionGainPositive = position ? position.totalGain >= 0 : true;

  if (!stock) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centered}>
          <Text style={[styles.emptyText, { color: colors.textSecondary }]}>
            Action introuvable
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
            <Ionicons name="arrow-back" size={24} color={colors.text} />
          </TouchableOpacity>
          <View style={styles.headerCenter}>
            <Text style={[styles.headerTitle, { color: colors.text }]}>{stock.name}</Text>
            <Text style={[styles.headerTicker, { color: colors.textSecondary }]}>
              {stock.ticker}
            </Text>
          </View>
          <View style={[styles.headerLogo, { backgroundColor: colors.primary }]}>
            <Text style={styles.headerLogoText}>{stock.name.charAt(0)}</Text>
          </View>
        </View>

        {/* Chart Section */}
        <View style={styles.chartSection}>
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
          <LineChart data={chartData} height={220} isPositive={isPositive} />
        </View>

        {/* Key Metrics */}
        <View style={styles.metricsGrid}>
          <GlassCard style={styles.metricCard}>
            <Text style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Prix actuel
            </Text>
            <Text style={[styles.metricValue, { color: colors.text }]}>
              {stock.currentPrice.toFixed(2)} €
            </Text>
          </GlassCard>
          <GlassCard style={styles.metricCard}>
            <Text style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Variation
            </Text>
            <Text
              style={[
                styles.metricValue,
                { color: isPositive ? colors.positive : colors.negative },
              ]}
            >
              {isPositive ? '+' : ''}{stock.dayChangePercent.toFixed(2)}%
            </Text>
          </GlassCard>
          <GlassCard style={styles.metricCard}>
            <Text style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Plus haut 52s
            </Text>
            <Text style={[styles.metricValue, { color: colors.text }]}>
              {stock.high52w.toFixed(2)} €
            </Text>
          </GlassCard>
          <GlassCard style={styles.metricCard}>
            <Text style={[styles.metricLabel, { color: colors.textSecondary }]}>
              Plus bas 52s
            </Text>
            <Text style={[styles.metricValue, { color: colors.text }]}>
              {stock.low52w.toFixed(2)} €
            </Text>
          </GlassCard>
        </View>

        {/* About */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>À propos</Text>
          <Text style={[styles.description, { color: colors.textSecondary }]}>
            {stock.description}
          </Text>
          <View style={styles.infoRow}>
            <Text style={[styles.infoText, { color: colors.textTertiary }]}>
              Secteur : {stock.sector}
            </Text>
            <Text style={[styles.infoSep, { color: colors.textTertiary }]}>|</Text>
            <Text style={[styles.infoText, { color: colors.textTertiary }]}>
              Bourse : {stock.exchange}
            </Text>
          </View>
        </View>

        {/* Position */}
        {position && (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.text }]}>Votre position</Text>
            <GlassCard>
              <View style={styles.positionRow}>
                <Text style={[styles.positionLabel, { color: colors.textSecondary }]}>
                  Nombre de parts
                </Text>
                <Text style={[styles.positionValue, { color: colors.text }]}>
                  {position.shares}
                </Text>
              </View>
              <View style={[styles.positionDivider, { backgroundColor: colors.border }]} />
              <View style={styles.positionRow}>
                <Text style={[styles.positionLabel, { color: colors.textSecondary }]}>
                  Prix moyen d&apos;achat
                </Text>
                <Text style={[styles.positionValue, { color: colors.text }]}>
                  {position.averageCost.toFixed(2)} €
                </Text>
              </View>
              <View style={[styles.positionDivider, { backgroundColor: colors.border }]} />
              <View style={styles.positionRow}>
                <Text style={[styles.positionLabel, { color: colors.textSecondary }]}>
                  Valeur totale
                </Text>
                <Text style={[styles.positionValue, { color: colors.text }]}>
                  {position.currentValue.toFixed(2)} €
                </Text>
              </View>
              <View style={[styles.positionDivider, { backgroundColor: colors.border }]} />
              <View style={styles.positionRow}>
                <Text style={[styles.positionLabel, { color: colors.textSecondary }]}>
                  Plus/moins-value
                </Text>
                <Text
                  style={[
                    styles.positionValue,
                    { color: positionGainPositive ? colors.positive : colors.negative },
                  ]}
                >
                  {positionGainPositive ? '+' : ''}{position.totalGain.toFixed(2)} € ({positionGainPositive ? '+' : ''}{position.totalGainPercent.toFixed(2)}%)
                </Text>
              </View>
              <View style={[styles.positionDivider, { backgroundColor: colors.border }]} />
              <View style={styles.positionRow}>
                <Text style={[styles.positionLabel, { color: colors.textSecondary }]}>
                  Date d&apos;acquisition
                </Text>
                <Text style={[styles.positionValue, { color: colors.text }]}>
                  {new Date(position.acquisitionDate).toLocaleDateString('fr-FR', {
                    day: 'numeric',
                    month: 'long',
                    year: 'numeric',
                  })}
                </Text>
              </View>
            </GlassCard>
          </View>
        )}

        {/* News */}
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: colors.text }]}>Actualités</Text>
          {mockNews.slice(0, 3).map((article) => (
            <TouchableOpacity key={article.id} activeOpacity={0.7} style={styles.newsItem}>
              <View style={styles.newsContent}>
                <Text
                  style={[styles.newsTitle, { color: colors.text }]}
                  numberOfLines={2}
                >
                  {article.title}
                </Text>
                <Text style={[styles.newsMeta, { color: colors.textTertiary }]}>
                  {article.source} · {new Date(article.date).toLocaleDateString('fr-FR', {
                    day: 'numeric',
                    month: 'short',
                  })}
                </Text>
              </View>
              <View style={[styles.newsImagePlaceholder, { backgroundColor: colors.surfaceLight }]}>
                <Ionicons name="image-outline" size={20} color={colors.textTertiary} />
              </View>
            </TouchableOpacity>
          ))}
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
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    fontSize: FontSize.md,
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
  headerCenter: {
    flex: 1,
  },
  headerTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
  },
  headerTicker: {
    fontSize: FontSize.sm,
  },
  headerLogo: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerLogoText: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
    color: '#FFFFFF',
  },
  chartSection: {
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.lg,
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
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: Spacing.md,
    gap: Spacing.sm,
    marginBottom: Spacing.lg,
  },
  metricCard: {
    width: '47%',
    flexGrow: 1,
  },
  metricLabel: {
    fontSize: FontSize.xs,
    marginBottom: Spacing.xs,
  },
  metricValue: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
  },
  section: {
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.lg,
  },
  sectionTitle: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
    marginBottom: Spacing.sm,
  },
  description: {
    fontSize: FontSize.md,
    lineHeight: 22,
    marginBottom: Spacing.sm,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  infoText: {
    fontSize: FontSize.sm,
  },
  infoSep: {
    fontSize: FontSize.sm,
  },
  positionRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Spacing.sm,
  },
  positionLabel: {
    fontSize: FontSize.sm,
  },
  positionValue: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.semibold,
  },
  positionDivider: {
    height: StyleSheet.hairlineWidth,
  },
  newsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Spacing.sm,
  },
  newsContent: {
    flex: 1,
    marginRight: Spacing.sm,
  },
  newsTitle: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
    marginBottom: 4,
  },
  newsMeta: {
    fontSize: FontSize.xs,
  },
  newsImagePlaceholder: {
    width: 60,
    height: 60,
    borderRadius: BorderRadius.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
