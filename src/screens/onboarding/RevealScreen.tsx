import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Animated,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useTheme } from '../../theme';
import { Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { GoldButton } from '../../components/common/GoldButton';
import { GlassCard } from '../../components/common/GlassCard';
import { AnimatedNumber } from '../../components/common/AnimatedNumber';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const CONFETTI_COUNT = 25;

interface ConfettiPiece {
  animY: Animated.Value;
  animX: number;
  delay: number;
  size: number;
  opacity: Animated.Value;
}

const RevealScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const { giftReveal } = useApp();

  const flipAnim = useRef(new Animated.Value(0)).current;
  const [isFlipped, setIsFlipped] = useState(false);

  // Confetti pieces
  const confettiPieces = useRef<ConfettiPiece[]>(
    Array.from({ length: CONFETTI_COUNT }, () => ({
      animY: new Animated.Value(-20),
      animX: Math.random() * SCREEN_WIDTH,
      delay: Math.random() * 2000,
      size: 6 + Math.random() * 8,
      opacity: new Animated.Value(1),
    }))
  ).current;

  useEffect(() => {
    const flipTimeout = setTimeout(() => {
      Animated.timing(flipAnim, {
        toValue: 180,
        duration: 800,
        useNativeDriver: true,
      }).start(() => {
        setIsFlipped(true);
        startConfetti();
      });
    }, 1000);

    return () => {
      clearTimeout(flipTimeout);
      flipAnim.stopAnimation();
      confettiPieces.forEach((piece) => {
        piece.animY.stopAnimation();
        piece.opacity.stopAnimation();
      });
    };
  }, []);

  const startConfetti = () => {
    confettiPieces.forEach((piece) => {
      Animated.sequence([
        Animated.delay(piece.delay),
        Animated.parallel([
          Animated.timing(piece.animY, {
            toValue: SCREEN_HEIGHT + 20,
            duration: 3000 + Math.random() * 2000,
            useNativeDriver: true,
          }),
          Animated.timing(piece.opacity, {
            toValue: 0,
            duration: 4000,
            useNativeDriver: true,
          }),
        ]),
      ]).start();
    });
  };

  const frontInterpolate = flipAnim.interpolate({
    inputRange: [0, 90, 180],
    outputRange: ['0deg', '90deg', '180deg'],
  });

  const backInterpolate = flipAnim.interpolate({
    inputRange: [0, 90, 180],
    outputRange: ['180deg', '90deg', '0deg'],
  });

  const frontOpacity = flipAnim.interpolate({
    inputRange: [0, 89, 90],
    outputRange: [1, 1, 0],
  });

  const backOpacity = flipAnim.interpolate({
    inputRange: [0, 89, 90],
    outputRange: [0, 0, 1],
  });

  const stocks = giftReveal?.stocks ?? [];
  const totalValue = giftReveal?.initialValue ?? 0;
  const personalMessage = giftReveal?.personalMessage ?? '';
  const senderName = giftReveal?.giftedBy ?? '';

  const handleDiscover = () => {
    navigation.reset({
      index: 0,
      routes: [{ name: 'MainTabs' }],
    });
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Confetti */}
      {confettiPieces.map((piece, index) => (
        <Animated.View
          key={index}
          style={[
            styles.confetti,
            {
              left: piece.animX,
              width: piece.size,
              height: piece.size,
              opacity: piece.opacity,
              transform: [{ translateY: piece.animY }],
            },
          ]}
        />
      ))}

      <ScrollView
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Card Front */}
        <Animated.View
          style={[
            styles.cardContainer,
            {
              opacity: frontOpacity,
              transform: [{ perspective: 1000 }, { rotateY: frontInterpolate }],
            },
          ]}
          pointerEvents={isFlipped ? 'none' : 'auto'}
        >
          <LinearGradient
            colors={['#C9A84C', '#A88A30', '#C9A84C']}
            style={styles.cardGradientBorder}
          >
            <View style={[styles.cardInner, { backgroundColor: '#0A0A0A' }]}>
              <Ionicons name="diamond-outline" size={48} color="#C9A84C" />
              <Text style={[styles.cardLogoText, { color: '#C9A84C' }]}>KREZUS</Text>
            </View>
          </LinearGradient>
        </Animated.View>

        {/* Card Back (Revealed Content) */}
        <Animated.View
          style={[
            styles.revealContainer,
            {
              opacity: backOpacity,
              transform: [{ perspective: 1000 }, { rotateY: backInterpolate }],
            },
          ]}
          pointerEvents={isFlipped ? 'auto' : 'none'}
        >
          <Text style={[styles.revealTitle, { color: '#C9A84C' }]}>Votre cadeau</Text>

          {/* Stocks List */}
          {stocks.map((stock: any, index: number) => (
            <View key={index} style={styles.stockRow}>
              <View style={styles.stockLogo}>
                <Text style={styles.stockLogoText}>
                  {stock.ticker ? stock.ticker.charAt(0) : '?'}
                </Text>
              </View>
              <View style={styles.stockInfo}>
                <Text style={[styles.stockName, { color: colors.text }]}>{stock.name}</Text>
                <Text style={[styles.stockTicker, { color: colors.text, opacity: 0.5 }]}>
                  {stock.ticker}
                </Text>
              </View>
              <Text style={[styles.stockShares, { color: '#C9A84C' }]}>
                {stock.shares} {stock.shares > 1 ? 'actions' : 'action'}
              </Text>
            </View>
          ))}

          {/* Total Value */}
          <View style={styles.valueContainer}>
            <Text style={[styles.valueLabel, { color: colors.text, opacity: 0.7 }]}>
              Valeur initiale :
            </Text>
            <AnimatedNumber value={totalValue} suffix=" €" />
          </View>

          {/* Nature du service : dit dès le premier écran, pas en petits caractères */}
          <Text style={[styles.simulationNote, { color: colors.text }]}>
            Portefeuille simulé : vous suivez ces actions aux cours réels du marché,
            sans argent engagé et sans titre détenu.
          </Text>

          {/* Personal Message */}
          {personalMessage ? (
            <GlassCard>
              <Text style={[styles.personalMessage, { color: colors.text }]}>
                "{personalMessage}"
              </Text>
            </GlassCard>
          ) : null}

          {/* Sender */}
          {senderName ? (
            <Text style={[styles.senderText, { color: colors.text, opacity: 0.7 }]}>
              De la part de : {senderName}
            </Text>
          ) : null}
        </Animated.View>

        {/* Bottom Button */}
        {isFlipped && (
          <View style={styles.buttonContainer}>
            <GoldButton title="Découvrir mon portefeuille" onPress={handleDiscover} />
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xxl,
    paddingBottom: Spacing.xxl,
    alignItems: 'center',
  },
  confetti: {
    position: 'absolute',
    backgroundColor: '#C9A84C',
    borderRadius: 2,
    zIndex: 10,
  },
  cardContainer: {
    width: SCREEN_WIDTH * 0.7,
    aspectRatio: 0.65,
    backfaceVisibility: 'hidden',
  },
  cardGradientBorder: {
    flex: 1,
    borderRadius: BorderRadius.lg,
    padding: 3,
  },
  cardInner: {
    flex: 1,
    borderRadius: BorderRadius.lg - 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cardLogoText: {
    fontSize: 28,
    fontWeight: FontWeight.bold as any,
    letterSpacing: 6,
    marginTop: Spacing.md,
  },
  revealContainer: {
    width: '100%',
    backfaceVisibility: 'hidden',
    position: 'absolute',
    top: Spacing.xxl,
    left: Spacing.xl,
    right: Spacing.xl,
  },
  revealTitle: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold as any,
    textAlign: 'center',
    marginBottom: Spacing.xl,
  },
  stockRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: Spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: '#FFFFFF11',
  },
  stockLogo: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#C9A84C22',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: Spacing.md,
  },
  stockLogoText: {
    color: '#C9A84C',
    fontSize: FontSize.md,
    fontWeight: FontWeight.bold as any,
  },
  stockInfo: {
    flex: 1,
  },
  stockName: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold as any,
  },
  stockTicker: {
    fontSize: FontSize.sm,
    marginTop: 2,
  },
  stockShares: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold as any,
  },
  valueContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: Spacing.xl,
    marginBottom: Spacing.lg,
  },
  valueLabel: {
    fontSize: FontSize.md,
    marginRight: Spacing.xs,
  },
  simulationNote: {
    fontSize: FontSize.sm,
    lineHeight: 19,
    textAlign: 'center',
    opacity: 0.6,
    marginBottom: Spacing.md,
    paddingHorizontal: Spacing.md,
  },
  personalMessage: {
    fontSize: FontSize.md,
    fontStyle: 'italic',
    textAlign: 'center',
    lineHeight: 24,
    padding: Spacing.md,
  },
  senderText: {
    fontSize: FontSize.md,
    textAlign: 'center',
    marginTop: Spacing.md,
  },
  buttonContainer: {
    width: '100%',
    marginTop: 'auto',
    paddingTop: Spacing.xl,
  },
});

export default RevealScreen;
