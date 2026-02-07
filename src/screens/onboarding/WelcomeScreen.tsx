import React, { useRef, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Dimensions,
  NativeSyntheticEvent,
  NativeScrollEvent,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../theme';
import { Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { GoldButton } from '../../components/common/GoldButton';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

interface Slide {
  title: string;
  subtitle: string;
  icon: keyof typeof Ionicons.glyphMap;
}

const slides: Slide[] = [
  {
    title: 'Bienvenue dans votre aventure boursière',
    subtitle:
      'Vous avez reçu un coffret cadeau contenant de vraies actions en bourse. Découvrez votre cadeau unique.',
    icon: 'gift-outline',
  },
  {
    title: 'Activez votre coffret',
    subtitle:
      'Scannez le QR code ou entrez le code d\'activation présent dans votre coffret pour révéler vos actions.',
    icon: 'qr-code-outline',
  },
  {
    title: 'Suivez vos investissements grandir',
    subtitle:
      'Suivez l\'évolution de votre portefeuille en temps réel et apprenez les bases de l\'investissement.',
    icon: 'trending-up-outline',
  },
];

const WelcomeScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const scrollViewRef = useRef<ScrollView>(null);
  const [activeIndex, setActiveIndex] = useState(0);

  const handleScroll = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const offsetX = event.nativeEvent.contentOffset.x;
    const index = Math.round(offsetX / SCREEN_WIDTH);
    setActiveIndex(index);
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        ref={scrollViewRef}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onScroll={handleScroll}
        scrollEventThrottle={16}
        style={styles.scrollView}
      >
        {slides.map((slide, index) => (
          <View key={index} style={[styles.slide, { width: SCREEN_WIDTH }]}>
            <Ionicons name={slide.icon} size={120} color="#C9A84C" />
            <Text style={[styles.title, { color: colors.text }]}>{slide.title}</Text>
            <Text style={[styles.subtitle, { color: colors.text, opacity: 0.7 }]}>
              {slide.subtitle}
            </Text>
          </View>
        ))}
      </ScrollView>

      <View style={styles.bottomContainer}>
        <View style={styles.pagination}>
          {slides.map((_, index) => (
            <View
              key={index}
              style={[
                styles.dot,
                {
                  backgroundColor: index === activeIndex ? '#C9A84C' : '#555555',
                },
              ]}
            />
          ))}
        </View>

        <View style={styles.buttonContainer}>
          <GoldButton title="Commencer" onPress={() => navigation.navigate('Activation')} />
        </View>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollView: {
    flex: 1,
  },
  slide: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: Spacing.xl,
  },
  title: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold as any,
    textAlign: 'center',
    marginTop: Spacing.xl,
    marginBottom: Spacing.md,
  },
  subtitle: {
    fontSize: FontSize.md,
    textAlign: 'center',
    lineHeight: 24,
    paddingHorizontal: Spacing.md,
  },
  bottomContainer: {
    paddingBottom: Spacing.xl,
    alignItems: 'center',
  },
  pagination: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: Spacing.lg,
  },
  dot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginHorizontal: 6,
  },
  buttonContainer: {
    paddingHorizontal: Spacing.xl,
    width: '100%',
  },
});

export default WelcomeScreen;
