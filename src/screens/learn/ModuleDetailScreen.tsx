import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Animated,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import * as Haptics from 'expo-haptics';
import { useTheme, Spacing, BorderRadius, FontSize, FontWeight } from '../../theme';
import { useApp } from '../../store/AppContext';
import { mockEducationModules } from '../../data/mockData';
import { GoldButton } from '../../components/common/GoldButton';
import { QuizQuestion } from '../../types';

type ModuleDetailParams = {
  ModuleDetail: { moduleId: string };
};

export const ModuleDetailScreen = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();
  const route = useRoute<RouteProp<ModuleDetailParams, 'ModuleDetail'>>();
  const { completeModule, completedModules } = useApp();
  const { moduleId } = route.params;

  const module = mockEducationModules.find((m) => m.id === moduleId);

  const [currentQuestionIndex, setCurrentQuestionIndex] = useState(0);
  const [selectedOption, setSelectedOption] = useState<number | null>(null);
  const [answeredQuestions, setAnsweredQuestions] = useState<Record<string, boolean>>({});
  const [quizStarted, setQuizStarted] = useState(false);
  const [quizFinished, setQuizFinished] = useState(false);
  const [scaleAnim] = useState(new Animated.Value(0));

  if (!module) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centered}>
          <Text style={[styles.emptyText, { color: colors.textSecondary }]}>
            Module introuvable
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  const currentQuestion: QuizQuestion | undefined = module.quiz[currentQuestionIndex];
  const totalQuestions = module.quiz.length;
  const correctCount = Object.values(answeredQuestions).filter(Boolean).length;
  const allCorrect = correctCount === totalQuestions;
  const alreadyCompleted = completedModules.includes(moduleId);

  const handleOptionSelect = useCallback(
    (optionIndex: number) => {
      if (selectedOption !== null) return;
      if (!currentQuestion) return;

      setSelectedOption(optionIndex);
      const isCorrect = optionIndex === currentQuestion.correctIndex;
      Haptics.notificationAsync(
        isCorrect ? Haptics.NotificationFeedbackType.Success : Haptics.NotificationFeedbackType.Error
      );

      setAnsweredQuestions((prev) => ({
        ...prev,
        [currentQuestion.id]: isCorrect,
      }));

      setTimeout(() => {
        if (currentQuestionIndex < totalQuestions - 1) {
          setCurrentQuestionIndex((prev) => prev + 1);
          setSelectedOption(null);
        } else {
          setQuizFinished(true);
          const allRight =
            Object.values({ ...answeredQuestions, [currentQuestion.id]: isCorrect }).filter(
              Boolean
            ).length === totalQuestions;
          if (allRight) {
            completeModule(moduleId);
            Animated.spring(scaleAnim, {
              toValue: 1,
              friction: 3,
              tension: 40,
              useNativeDriver: true,
            }).start();
          }
        }
      }, 1200);
    },
    [
      selectedOption,
      currentQuestion,
      currentQuestionIndex,
      totalQuestions,
      answeredQuestions,
      completeModule,
      moduleId,
      scaleAnim,
    ]
  );

  const getOptionStyle = (optionIndex: number) => {
    if (selectedOption === null) {
      return { backgroundColor: colors.surface, borderColor: colors.border };
    }
    if (!currentQuestion) {
      return { backgroundColor: colors.surface, borderColor: colors.border };
    }
    if (optionIndex === currentQuestion.correctIndex) {
      return { backgroundColor: colors.positiveLight, borderColor: colors.positive };
    }
    if (optionIndex === selectedOption && optionIndex !== currentQuestion.correctIndex) {
      return { backgroundColor: colors.negativeLight, borderColor: colors.negative };
    }
    return { backgroundColor: colors.surface, borderColor: colors.border };
  };

  const getOptionTextColor = (optionIndex: number) => {
    if (selectedOption === null) return colors.text;
    if (!currentQuestion) return colors.text;
    if (optionIndex === currentQuestion.correctIndex) return colors.positive;
    if (optionIndex === selectedOption && optionIndex !== currentQuestion.correctIndex)
      return colors.negative;
    return colors.textTertiary;
  };

  const resetQuiz = () => {
    setCurrentQuestionIndex(0);
    setSelectedOption(null);
    setAnsweredQuestions({});
    setQuizFinished(false);
    setQuizStarted(false);
    scaleAnim.setValue(0);
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
            <Ionicons name="arrow-back" size={24} color={colors.text} />
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: colors.text }]} numberOfLines={1}>
            {module.title}
          </Text>
          <View style={styles.headerSpacer} />
        </View>

        {/* Content */}
        <View style={styles.contentSection}>
          {module.content.split('\n\n').map((paragraph, index) => (
            <Text
              key={index}
              style={[styles.paragraph, { color: colors.textSecondary }]}
            >
              {paragraph}
            </Text>
          ))}
        </View>

        {/* Quiz Section */}
        <View style={styles.quizSection}>
          <Text style={[styles.quizTitle, { color: colors.text }]}>Quiz</Text>

          {!quizStarted && !alreadyCompleted && (
            <GoldButton
              title="Commencer le quiz"
              onPress={() => setQuizStarted(true)}
            />
          )}

          {alreadyCompleted && !quizStarted && (
            <View style={styles.completedBanner}>
              <Ionicons name="checkmark-circle" size={24} color={colors.positive} />
              <Text style={[styles.completedText, { color: colors.positive }]}>
                Module déjà complété !
              </Text>
            </View>
          )}

          {quizStarted && !quizFinished && currentQuestion && (
            <View>
              <Text style={[styles.questionCounter, { color: colors.textTertiary }]}>
                Question {currentQuestionIndex + 1}/{totalQuestions}
              </Text>
              <Text style={[styles.questionText, { color: colors.text }]}>
                {currentQuestion.question}
              </Text>
              {currentQuestion.options.map((option, index) => (
                <TouchableOpacity
                  key={index}
                  activeOpacity={selectedOption !== null ? 1 : 0.7}
                  onPress={() => handleOptionSelect(index)}
                  style={[styles.optionButton, getOptionStyle(index)]}
                >
                  <Text style={[styles.optionText, { color: getOptionTextColor(index) }]}>
                    {option}
                  </Text>
                  {selectedOption !== null && index === currentQuestion.correctIndex && (
                    <Ionicons name="checkmark-circle" size={20} color={colors.positive} />
                  )}
                  {selectedOption === index &&
                    index !== currentQuestion.correctIndex && (
                      <Ionicons name="close-circle" size={20} color={colors.negative} />
                    )}
                </TouchableOpacity>
              ))}
            </View>
          )}

          {quizFinished && (
            <View style={styles.resultSection}>
              {allCorrect ? (
                <>
                  <Animated.View
                    style={[
                      styles.bravoContainer,
                      { transform: [{ scale: scaleAnim }] },
                    ]}
                  >
                    <Ionicons name="trophy" size={48} color={colors.primary} />
                    <Text style={[styles.bravoText, { color: colors.primary }]}>
                      Bravo !
                    </Text>
                    <Text style={[styles.resultSubtext, { color: colors.textSecondary }]}>
                      {correctCount}/{totalQuestions} bonnes réponses
                    </Text>
                  </Animated.View>
                </>
              ) : (
                <View style={styles.resultContainer}>
                  <Ionicons name="refresh-circle" size={48} color={colors.textSecondary} />
                  <Text style={[styles.resultText, { color: colors.text }]}>
                    {correctCount}/{totalQuestions} bonnes réponses
                  </Text>
                  <Text style={[styles.resultSubtext, { color: colors.textSecondary }]}>
                    Réessayez pour obtenir toutes les bonnes réponses !
                  </Text>
                  <TouchableOpacity onPress={resetQuiz} style={styles.retryButton}>
                    <Text style={[styles.retryText, { color: colors.primary }]}>
                      Réessayer
                    </Text>
                  </TouchableOpacity>
                </View>
              )}
              <View style={styles.backButtonContainer}>
                <GoldButton
                  title="Retour aux modules"
                  onPress={() => navigation.goBack()}
                />
              </View>
            </View>
          )}
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
  headerTitle: {
    flex: 1,
    fontSize: FontSize.lg,
    fontWeight: FontWeight.bold,
    textAlign: 'center',
  },
  headerSpacer: {
    width: 32 + Spacing.xs * 2,
  },
  contentSection: {
    paddingHorizontal: Spacing.md,
    marginBottom: Spacing.xl,
  },
  paragraph: {
    fontSize: FontSize.md,
    lineHeight: 24,
    marginBottom: Spacing.md,
  },
  quizSection: {
    paddingHorizontal: Spacing.md,
  },
  quizTitle: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
    marginBottom: Spacing.md,
  },
  completedBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    paddingVertical: Spacing.md,
  },
  completedText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  questionCounter: {
    fontSize: FontSize.sm,
    marginBottom: Spacing.xs,
  },
  questionText: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
    marginBottom: Spacing.md,
    lineHeight: 24,
  },
  optionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
    borderWidth: 1,
    marginBottom: Spacing.sm,
  },
  optionText: {
    fontSize: FontSize.md,
    flex: 1,
    marginRight: Spacing.sm,
  },
  resultSection: {
    alignItems: 'center',
    paddingTop: Spacing.lg,
  },
  bravoContainer: {
    alignItems: 'center',
    gap: Spacing.sm,
  },
  bravoText: {
    fontSize: FontSize.hero,
    fontWeight: FontWeight.heavy,
  },
  resultContainer: {
    alignItems: 'center',
    gap: Spacing.sm,
  },
  resultText: {
    fontSize: FontSize.xl,
    fontWeight: FontWeight.bold,
  },
  resultSubtext: {
    fontSize: FontSize.md,
    textAlign: 'center',
  },
  retryButton: {
    paddingVertical: Spacing.sm,
  },
  retryText: {
    fontSize: FontSize.md,
    fontWeight: FontWeight.semibold,
  },
  backButtonContainer: {
    width: '100%',
    marginTop: Spacing.xl,
  },
});
