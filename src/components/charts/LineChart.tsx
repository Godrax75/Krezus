import React, { useState, useRef, useEffect } from 'react';
import { View, StyleSheet, Dimensions, PanResponder, Text, Animated } from 'react-native';
import Svg, { Path, Defs, LinearGradient as SvgLinearGradient, Stop, Circle } from 'react-native-svg';
import { useTheme, FontSize, FontWeight, Spacing, BorderRadius } from '../../theme';
import { ChartDataPoint } from '../../types';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

interface LineChartProps {
  data: ChartDataPoint[];
  height?: number;
  width?: number;
  showGradient?: boolean;
  isPositive?: boolean;
}

export const LineChart = ({
  data,
  height = 200,
  width = SCREEN_WIDTH - 32,
  showGradient = true,
  isPositive = true,
}: LineChartProps) => {
  const { colors } = useTheme();
  const [tooltipData, setTooltipData] = useState<{ x: number; y: number; value: number; date: string } | null>(null);
  const drawAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    drawAnim.setValue(0);
    Animated.timing(drawAnim, {
      toValue: 1,
      duration: 1200,
      useNativeDriver: false,
    }).start();
  }, [data, drawAnim]);

  if (!data || data.length === 0) return null;

  const padding = { top: 20, bottom: 20, left: 0, right: 0 };
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const values = data.map(d => d.value);
  const minValue = Math.min(...values) * 0.995;
  const maxValue = Math.max(...values) * 1.005;
  const valueRange = maxValue - minValue || 1;

  const getX = (index: number) => padding.left + (index / (data.length - 1)) * chartWidth;
  const getY = (value: number) => padding.top + chartHeight - ((value - minValue) / valueRange) * chartHeight;

  const pathData = data.map((point, i) => {
    const x = getX(i);
    const y = getY(point.value);
    return `${i === 0 ? 'M' : 'L'} ${x} ${y}`;
  }).join(' ');

  const gradientPathData = `${pathData} L ${getX(data.length - 1)} ${height} L ${getX(0)} ${height} Z`;

  const lineColor = isPositive ? colors.positive : colors.negative;

  const panResponder = PanResponder.create({
    onStartShouldSetPanResponder: () => false,
    onMoveShouldSetPanResponder: (_, gestureState) =>
      Math.abs(gestureState.dx) > Math.abs(gestureState.dy) && Math.abs(gestureState.dx) > 10,
    onPanResponderGrant: (_, gestureState) => handleTouch(gestureState.x0),
    onPanResponderMove: (_, gestureState) => handleTouch(gestureState.moveX),
    onPanResponderRelease: () => setTooltipData(null),
    onPanResponderTerminate: () => setTooltipData(null),
  });

  const handleTouch = (touchX: number) => {
    const adjustedX = touchX - 16;
    const index = Math.round((adjustedX - padding.left) / chartWidth * (data.length - 1));
    const clampedIndex = Math.max(0, Math.min(data.length - 1, index));
    const point = data[clampedIndex];
    const date = new Date(point.timestamp);
    setTooltipData({
      x: getX(clampedIndex),
      y: getY(point.value),
      value: point.value,
      date: date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' }),
    });
  };

  return (
    <View style={styles.container} {...panResponder.panHandlers}>
      <Svg width={width} height={height}>
        <Defs>
          <SvgLinearGradient id="gradient" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={lineColor} stopOpacity="0.3" />
            <Stop offset="1" stopColor={lineColor} stopOpacity="0" />
          </SvgLinearGradient>
        </Defs>
        {showGradient && <Path d={gradientPathData} fill="url(#gradient)" />}
        <Path d={pathData} fill="none" stroke={lineColor} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />
        {tooltipData && (
          <Circle cx={tooltipData.x} cy={tooltipData.y} r={6} fill={lineColor} stroke={colors.background} strokeWidth={2} />
        )}
      </Svg>
      {tooltipData && (
        <View style={[styles.tooltip, { left: Math.min(tooltipData.x - 50, width - 120), backgroundColor: colors.surface, borderColor: colors.border }]}>
          <Text style={[styles.tooltipValue, { color: colors.text }]}>{tooltipData.value.toFixed(2)} €</Text>
          <Text style={[styles.tooltipDate, { color: colors.textSecondary }]}>{tooltipData.date}</Text>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'relative',
  },
  tooltip: {
    position: 'absolute',
    top: 0,
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    borderRadius: BorderRadius.sm,
    borderWidth: 1,
  },
  tooltipValue: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.bold,
  },
  tooltipDate: {
    fontSize: FontSize.xs,
  },
});
