import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Platform,
  KeyboardAvoidingView,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../theme';
import { Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { GoldButton } from '../../components/common/GoldButton';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const SignupScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const { setUser, completeOnboarding } = useApp();

  const [firstName, setFirstName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [cguAccepted, setCguAccepted] = useState(false);
  const [emailError, setEmailError] = useState('');

  const passwordStrength = useMemo(() => {
    if (password.length === 0) return 0;
    if (password.length < 4) return 1;
    if (password.length < 8) return 2;
    if (password.length < 12) return 3;
    return 4;
  }, [password]);

  const strengthColors = ['#FF4444', '#FF8800', '#FFCC00', '#4CAF50'];
  const strengthColor = passwordStrength > 0 ? strengthColors[passwordStrength - 1] : '#333';

  const isFormValid = useMemo(() => {
    return (
      firstName.trim().length > 0 &&
      EMAIL_REGEX.test(email.trim()) &&
      password.length >= 8 &&
      cguAccepted
    );
  }, [firstName, email, password, cguAccepted]);

  const handleEmailChange = (text: string) => {
    setEmail(text);
    if (text.trim().length === 0) {
      setEmailError('');
    } else if (!EMAIL_REGEX.test(text.trim())) {
      setEmailError("Format d'email invalide");
    } else {
      setEmailError('');
    }
  };

  const handleSocialPress = (provider: 'Apple' | 'Google') => {
    Alert.alert(
      'Bientôt disponible',
      `L'inscription via ${provider} sera disponible prochainement.`
    );
  };

  const handleSubmit = () => {
    if (!isFormValid) return;

    setUser({
      id: '1',
      firstName: firstName.trim(),
      email: email.trim(),
      activationDate: new Date().toISOString(),
    });
    completeOnboarding();
    navigation.navigate('Reveal');
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.flex}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <Text style={[styles.title, { color: colors.text }]}>
            Créons votre profil d'investisseur
          </Text>

          {/* Prénom */}
          <View style={styles.fieldContainer}>
            <Text style={[styles.label, { color: colors.text, opacity: 0.7 }]}>Prénom</Text>
            <TextInput
              style={[styles.input, { color: colors.text, borderColor: '#C9A84C55', backgroundColor: '#FFFFFF0A' }]}
              value={firstName}
              onChangeText={setFirstName}
              placeholder="Votre prénom"
              placeholderTextColor="#FFFFFF44"
              autoCapitalize="words"
            />
          </View>

          {/* Email */}
          <View style={styles.fieldContainer}>
            <Text style={[styles.label, { color: colors.text, opacity: 0.7 }]}>Email</Text>
            <TextInput
              style={[
                styles.input,
                {
                  color: colors.text,
                  borderColor: emailError ? '#FF4444' : '#C9A84C55',
                  backgroundColor: '#FFFFFF0A',
                },
              ]}
              value={email}
              onChangeText={handleEmailChange}
              placeholder="votre@email.com"
              placeholderTextColor="#FFFFFF44"
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
            />
            {emailError ? (
              <Text style={styles.emailErrorText}>{emailError}</Text>
            ) : null}
          </View>

          {/* Mot de passe */}
          <View style={styles.fieldContainer}>
            <Text style={[styles.label, { color: colors.text, opacity: 0.7 }]}>Mot de passe</Text>
            <View style={styles.passwordContainer}>
              <TextInput
                style={[
                  styles.input,
                  styles.passwordInput,
                  { color: colors.text, borderColor: '#C9A84C55', backgroundColor: '#FFFFFF0A' },
                ]}
                value={password}
                onChangeText={setPassword}
                placeholder="Minimum 8 caractères"
                placeholderTextColor="#FFFFFF44"
                secureTextEntry={!showPassword}
                autoCapitalize="none"
              />
              <TouchableOpacity
                style={styles.eyeButton}
                onPress={() => setShowPassword(!showPassword)}
              >
                <Ionicons
                  name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                  size={22}
                  color="#C9A84C"
                />
              </TouchableOpacity>
            </View>
            {/* Password strength indicator */}
            <View style={styles.strengthBarContainer}>
              {[1, 2, 3, 4].map((level) => (
                <View
                  key={level}
                  style={[
                    styles.strengthSegment,
                    {
                      backgroundColor:
                        passwordStrength >= level ? strengthColor : '#333333',
                    },
                  ]}
                />
              ))}
            </View>
          </View>

          {/* Divider */}
          <View style={styles.dividerContainer}>
            <View style={[styles.dividerLine, { backgroundColor: '#FFFFFF22' }]} />
            <Text style={[styles.dividerText, { color: colors.text, opacity: 0.5 }]}>ou</Text>
            <View style={[styles.dividerLine, { backgroundColor: '#FFFFFF22' }]} />
          </View>

          {/* Apple Button */}
          <TouchableOpacity
            style={[styles.socialButton, { borderColor: '#FFFFFF33', opacity: 0.6 }]}
            activeOpacity={0.7}
            onPress={() => handleSocialPress('Apple')}
          >
            <Ionicons name="logo-apple" size={22} color="#FFFFFF" />
            <Text style={[styles.socialButtonText, { color: colors.text }]}>
              Continuer avec Apple
            </Text>
          </TouchableOpacity>

          {/* Google Button */}
          <TouchableOpacity
            style={[styles.socialButton, { borderColor: '#FFFFFF33', opacity: 0.6 }]}
            activeOpacity={0.7}
            onPress={() => handleSocialPress('Google')}
          >
            <Ionicons name="logo-google" size={20} color="#FFFFFF" />
            <Text style={[styles.socialButtonText, { color: colors.text }]}>
              Continuer avec Google
            </Text>
          </TouchableOpacity>

          {/* Social buttons hint */}
          <Text style={styles.socialHintText}>Bientôt disponible</Text>

          {/* CGU Checkbox */}
          <TouchableOpacity
            style={styles.cguContainer}
            onPress={() => setCguAccepted(!cguAccepted)}
            activeOpacity={0.7}
          >
            <View
              style={[
                styles.checkbox,
                {
                  borderColor: cguAccepted ? '#C9A84C' : '#FFFFFF44',
                  backgroundColor: cguAccepted ? '#C9A84C' : 'transparent',
                },
              ]}
            >
              {cguAccepted && <Ionicons name="checkmark" size={14} color="#0A0A0A" />}
            </View>
            <Text style={[styles.cguText, { color: colors.text, opacity: 0.7 }]}>
              J'accepte les Conditions Générales d'Utilisation
            </Text>
          </TouchableOpacity>

          {/* Submit */}
          <View style={styles.submitContainer}>
            <GoldButton
              title="Créer mon compte"
              onPress={handleSubmit}
              disabled={!isFormValid}
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  flex: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xl,
    paddingBottom: Spacing.xxl,
  },
  title: {
    fontSize: FontSize.xxl,
    fontWeight: FontWeight.bold as any,
    textAlign: 'center',
    marginBottom: Spacing.xl,
  },
  fieldContainer: {
    marginBottom: Spacing.md,
  },
  label: {
    fontSize: FontSize.sm,
    fontWeight: FontWeight.medium as any,
    marginBottom: Spacing.xs,
  },
  input: {
    fontSize: FontSize.md,
    padding: Spacing.md,
    borderWidth: 1,
    borderRadius: BorderRadius.md,
  },
  emailErrorText: {
    color: '#FF4444',
    fontSize: FontSize.sm,
    marginTop: 4,
  },
  passwordContainer: {
    position: 'relative',
  },
  passwordInput: {
    paddingRight: 50,
  },
  eyeButton: {
    position: 'absolute',
    right: Spacing.md,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
  },
  strengthBarContainer: {
    flexDirection: 'row',
    marginTop: Spacing.xs,
    gap: 4,
  },
  strengthSegment: {
    flex: 1,
    height: 4,
    borderRadius: 2,
  },
  dividerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: Spacing.lg,
  },
  dividerLine: {
    flex: 1,
    height: 1,
  },
  dividerText: {
    marginHorizontal: Spacing.md,
    fontSize: FontSize.sm,
  },
  socialButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: Spacing.md,
    borderWidth: 1,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.sm,
  },
  socialButtonText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold as any,
    marginLeft: Spacing.sm,
  },
  socialHintText: {
    fontSize: FontSize.xs,
    color: '#FFFFFF66',
    textAlign: 'center',
    marginBottom: Spacing.sm,
  },
  cguContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: Spacing.lg,
    marginBottom: Spacing.md,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderWidth: 2,
    borderRadius: 4,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: Spacing.sm,
  },
  cguText: {
    fontSize: FontSize.sm,
    flex: 1,
  },
  submitContainer: {
    marginTop: Spacing.md,
  },
});

export default SignupScreen;
