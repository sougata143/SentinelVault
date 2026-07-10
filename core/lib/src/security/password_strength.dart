import 'package:zxcvbnm/languages/en.dart' as en;
import 'package:zxcvbnm/zxcvbnm.dart';

/// Represents the structured result of a password strength analysis.
class PasswordStrengthResult {
  /// The password strength score, from 0 (very weak) to 4 (very strong).
  final int score;

  /// Human-readable estimated crack time for offline attacks.
  final String estimatedCrackTime;

  /// List of matched weakness patterns (e.g. keyboard sequence, repeat).
  final List<String> matchedPatterns;

  /// Actionable suggestions to improve password strength.
  final List<String> suggestions;

  /// Creates a new [PasswordStrengthResult].
  PasswordStrengthResult({
    required this.score,
    required this.estimatedCrackTime,
    required this.matchedPatterns,
    required this.suggestions,
  });

  /// Converts the result to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'estimated_crack_time': estimatedCrackTime,
      'matched_patterns': matchedPatterns,
      'suggestions': suggestions,
    };
  }
}

/// Evaluates password strength locally and offline.
class PasswordAnalyzer {
  /// Analyzes a password using pattern-and-entropy (zxcvbn-style) matching.
  /// 
  /// Optionally accepts [userInputs] (e.g. username, email) to penalize passwords
  /// containing personal info.
  /// 
  /// Security invariant: Runs entirely locally and does not transmit or log the password.
  static PasswordStrengthResult analyze(String password, {List<String> userInputs = const []}) {
    if (password.isEmpty) {
      return PasswordStrengthResult(
        score: 0,
        estimatedCrackTime: 'instant',
        matchedPatterns: const [],
        suggestions: const ['Enter a password'],
      );
    }

    // Initialize the zxcvbnm engine with standard English dictionaries
    final zxcvbnm = Zxcvbnm(
      dictionaries: en.dictionaries,
    );

    // Call the engine with user-specific inputs as an optional positional argument
    final result = zxcvbnm(password, userInputs.isNotEmpty ? userInputs : null);

    // Extract unique matched patterns based on runtimeType
    final matched = result.sequence.map((m) {
      final typeStr = m.runtimeType.toString();
      if (typeStr.endsWith('Match')) {
        final baseName = typeStr.substring(0, typeStr.length - 5);
        final snakeName = baseName
            .split(RegExp('(?=[A-Z])'))
            .map((w) => w.toLowerCase())
            .join('_')
            .replaceAll(RegExp('^_'), '');
        return snakeName;
      }
      return typeStr.toLowerCase();
    }).toSet().toList();

    // Consolidate suggestions and warnings
    final suggestions = List<String>.from(result.feedback.suggestions);
    final warning = result.feedback.warning;
    if (warning != null && warning.isNotEmpty) {
      suggestions.insert(0, warning);
    }

    return PasswordStrengthResult(
      score: result.score,
      estimatedCrackTime: result.crackTimesDisplay.offlineFastHashing1e10PerSecond,
      matchedPatterns: matched,
      suggestions: suggestions,
    );
  }
}
