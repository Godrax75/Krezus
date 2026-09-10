import React, { useState, useRef, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Alert,
  Animated,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Haptics from 'expo-haptics';
import { useTheme } from '../../theme';
import { Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { GoldButton } from '../../components/common/GoldButton';

const ActivationScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const { setActivationCode } = useApp();

  const [showManualInput, setShowManualInput] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  const [permission, requestPermission] = useCameraPermissions();

  const shakeAnim = useRef(new Animated.Value(0)).current;
  const successOpacity = useRef(new Animated.Value(0)).current;

  const formatCode = (text: string): string => {
    const cleaned = text.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    const parts: string[] = [];
    for (let i = 0; i < cleaned.length && i < 12; i += 4) {
      parts.push(cleaned.slice(i, i + 4));
    }
    return parts.join('-');
  };

  const handleCodeChange = (text: string) => {
    setError('');
    setCode(formatCode(text));
  };

  const triggerShake = () => {
    Animated.sequence([
      Animated.timing(shakeAnim, { toValue: 10, duration: 50, useNativeDriver: true }),
      Animated.timing(shakeAnim, { toValue: -10, duration: 50, useNativeDriver: true }),
      Animated.timing(shakeAnim, { toValue: 10, duration: 50, useNativeDriver: true }),
      Animated.timing(shakeAnim, { toValue: -10, duration: 50, useNativeDriver: true }),
      Animated.timing(shakeAnim, { toValue: 0, duration: 50, useNativeDriver: true }),
    ]).start();
  };

  const validateAndSubmit = useCallback((codeValue: string) => {
    const rawCode = codeValue.replace(/-/g, '');

    if (rawCode.length < 12) {
      setError('Code invalide. Veuillez réessayer.');
      triggerShake();
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      return;
    }

    setActivationCode(codeValue);
    setSuccess(true);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);

    Animated.timing(successOpacity, {
      toValue: 1,
      duration: 500,
      useNativeDriver: true,
    }).start();

    setTimeout(() => {
      navigation.navigate('Signup');
    }, 1500);
  }, [setActivationCode, navigation, successOpacity, shakeAnim]);

  const handleSubmit = () => {
    validateAndSubmit(code);
  };

  const handleScanQR = async () => {
    if (!permission?.granted) {
      const result = await requestPermission();
      if (!result.granted) {
        Alert.alert(
          'Permission refusée',
          'L\'accès à la caméra est nécessaire pour scanner le QR code. Vous pouvez entrer le code manuellement.',
          [
            {
              text: 'Saisie manuelle',
              onPress: () => {
                setShowManualInput(true);
              },
            },
          ],
        );
        return;
      }
    }
    setShowScanner(true);
  };

  const handleBarcodeScanned = useCallback(({ data }: { data: string }) => {
    const formatted = formatCode(data);
    setCode(formatted);
    setShowScanner(false);
    validateAndSubmit(formatted);
  }, [validateAndSubmit]);

  if (success) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <Animated.View style={[styles.successContainer, { opacity: successOpacity }]}>
          <Ionicons name="checkmark-circle" size={80} color="#4CAF50" />
          <Text style={[styles.successText, { color: colors.text }]}>Code validé !</Text>
        </Animated.View>
      </SafeAreaView>
    );
  }

  if (showScanner) {
    return (
      <View style={styles.scannerContainer}>
        <CameraView
          style={StyleSheet.absoluteFill}
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={handleBarcodeScanned}
        />
        <View style={styles.scannerOverlay}>
          <View style={styles.scannerTopBar}>
            <TouchableOpacity
              style={styles.scannerCloseButton}
              onPress={() => setShowScanner(false)}
              activeOpacity={0.7}
            >
              <Ionicons name="close" size={32} color="#FFFFFF" />
            </TouchableOpacity>
          </View>
          <View style={styles.scannerFrameRow}>
            <View style={styles.scannerSideMask} />
            <View style={styles.scannerFrame}>
              <View style={[styles.scannerCorner, styles.scannerCornerTL]} />
              <View style={[styles.scannerCorner, styles.scannerCornerTR]} />
              <View style={[styles.scannerCorner, styles.scannerCornerBL]} />
              <View style={[styles.scannerCorner, styles.scannerCornerBR]} />
            </View>
            <View style={styles.scannerSideMask} />
          </View>
          <View style={styles.scannerBottomMask}>
            <Text style={styles.scannerHintText}>
              Placez le QR code de votre coffret dans le cadre
            </Text>
          </View>
        </View>
      </View>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardView}
      >
        <Text style={[styles.title, { color: colors.text }]}>
          Activez votre coffret cadeau
        </Text>

        <TouchableOpacity
          style={[styles.optionCard, { borderColor: '#C9A84C33' }]}
          onPress={handleScanQR}
          activeOpacity={0.7}
        >
          <Ionicons name="qr-code-outline" size={32} color="#C9A84C" />
          <Text style={[styles.optionText, { color: colors.text }]}>Scanner le QR Code</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.optionCard, { borderColor: '#C9A84C33' }]}
          onPress={() => setShowManualInput(!showManualInput)}
          activeOpacity={0.7}
        >
          <Ionicons name="keypad-outline" size={32} color="#C9A84C" />
          <Text style={[styles.optionText, { color: colors.text }]}>
            Entrer le code manuellement
          </Text>
        </TouchableOpacity>

        {showManualInput && (
          <View style={styles.inputContainer}>
            <Animated.View style={{ transform: [{ translateX: shakeAnim }] }}>
              <TextInput
                style={[
                  styles.input,
                  {
                    color: colors.text,
                    borderColor: error ? '#FF4444' : '#C9A84C55',
                    backgroundColor: '#FFFFFF0A',
                  },
                ]}
                placeholder="XXXX-XXXX-XXXX"
                placeholderTextColor="#FFFFFF44"
                value={code}
                onChangeText={handleCodeChange}
                autoCapitalize="characters"
                maxLength={14}
              />
            </Animated.View>
            {error ? <Text style={styles.errorText}>{error}</Text> : null}
          </View>
        )}

        <View style={styles.buttonContainer}>
          <GoldButton title="Valider" onPress={handleSubmit} />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const SCANNER_FRAME_SIZE = 250;
const CORNER_SIZE = 30;
const CORNER_WIDTH = 4;

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  keyboardView: {
    flex: 1,
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xxl,
  },
  title: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold as any,
    textAlign: 'center',
    marginBottom: Spacing.xxl,
  },
  optionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: Spacing.lg,
    borderRadius: BorderRadius.lg,
    borderWidth: 1,
    backgroundColor: '#FFFFFF08',
    marginBottom: Spacing.md,
  },
  optionText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold as any,
    marginLeft: Spacing.md,
  },
  inputContainer: {
    marginTop: Spacing.md,
  },
  input: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold as any,
    textAlign: 'center',
    padding: Spacing.md,
    borderWidth: 1,
    borderRadius: BorderRadius.md,
    letterSpacing: 2,
  },
  errorText: {
    color: '#FF4444',
    fontSize: FontSize.sm,
    textAlign: 'center',
    marginTop: Spacing.sm,
  },
  buttonContainer: {
    marginTop: Spacing.xl,
  },
  successContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  successText: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold as any,
    marginTop: Spacing.md,
  },
  // Scanner styles
  scannerContainer: {
    flex: 1,
    backgroundColor: '#000000',
  },
  scannerOverlay: {
    ...StyleSheet.absoluteFill,
    justifyContent: 'space-between',
  },
  scannerTopBar: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'flex-start',
    alignItems: 'flex-end',
    paddingTop: 60,
    paddingRight: 20,
  },
  scannerCloseButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  scannerFrameRow: {
    flexDirection: 'row',
    height: SCANNER_FRAME_SIZE,
  },
  scannerSideMask: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
  },
  scannerFrame: {
    width: SCANNER_FRAME_SIZE,
    height: SCANNER_FRAME_SIZE,
  },
  scannerCorner: {
    position: 'absolute',
    width: CORNER_SIZE,
    height: CORNER_SIZE,
  },
  scannerCornerTL: {
    top: 0,
    left: 0,
    borderTopWidth: CORNER_WIDTH,
    borderLeftWidth: CORNER_WIDTH,
    borderColor: '#C9A84C',
  },
  scannerCornerTR: {
    top: 0,
    right: 0,
    borderTopWidth: CORNER_WIDTH,
    borderRightWidth: CORNER_WIDTH,
    borderColor: '#C9A84C',
  },
  scannerCornerBL: {
    bottom: 0,
    left: 0,
    borderBottomWidth: CORNER_WIDTH,
    borderLeftWidth: CORNER_WIDTH,
    borderColor: '#C9A84C',
  },
  scannerCornerBR: {
    bottom: 0,
    right: 0,
    borderBottomWidth: CORNER_WIDTH,
    borderRightWidth: CORNER_WIDTH,
    borderColor: '#C9A84C',
  },
  scannerBottomMask: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    alignItems: 'center',
    paddingTop: 30,
  },
  scannerHintText: {
    color: '#FFFFFF',
    fontSize: FontSize.md,
    textAlign: 'center',
    paddingHorizontal: Spacing.xl,
  },
});

export default ActivationScreen;
