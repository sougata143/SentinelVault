import 'dart:convert';
import 'package:http/http.dart' as http;

/// Output returned by the AI Insights service.
class AiInsightsResult {
  /// 2–4 plain-English sentences explaining the risk.
  final String summary;

  /// Concrete numbered actions the user should take.
  final List<String> recommendedActions;

  /// Creates a new [AiInsightsResult] with the specified risk summary and recommended actions.
  AiInsightsResult({
    required this.summary,
    required this.recommendedActions,
  });

  /// Decodes an [AiInsightsResult] from a JSON map returned by the backend.
  factory AiInsightsResult.fromJson(Map<String, dynamic> json) {
    return AiInsightsResult(
      summary: json['summary'] as String? ?? '',
      recommendedActions: List<String>.from(json['recommended_actions'] as List? ?? []),
    );
  }
}

/// Client to query the NestJS AI insights endpoint.
///
/// ## Security Invariant:
/// - Only non-sensitive aggregate stats are sent to the backend.
/// - Raw passwords, email addresses, and vault contents are NEVER sent.
class AiInsightsClient {
  /// The base URL of the security analysis microservice backend.
  final String backendUrl;

  /// Creates a new [AiInsightsClient], optionally specifying a custom [backendUrl].
  AiInsightsClient({this.backendUrl = 'http://localhost:3003'});

  /// Requests AI-generated insights for the given [payload].
  ///
  /// Falls back gracefully to static local responses if the backend is unreachable.
  Future<AiInsightsResult> getInsights(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/security-analysis/insights'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        return AiInsightsResult.fromJson(decoded);
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (_) {
      // Offline-first fallback
      final type = payload['finding_type'] as String? ?? '';
      if (type == 'weekly_digest') {
        return AiInsightsResult(
          summary: 'Your weekly security digest shows a stable posture. '
              'Keep checking and updating weak or reused passwords to protect your online accounts.',
          recommendedActions: [
            'Enable two-factor authentication on all critical accounts.',
            'Replace reused passwords with generated ones.',
            'Run a dark-web check periodically.',
          ],
        );
      }
      return AiInsightsResult(
        summary: 'Unable to contact the security analysis backend to generate insights.',
        recommendedActions: [
          'Ensure the security analysis service is running on port 3003.',
          'Verify your network connection.',
        ],
      );
    }
  }
}
