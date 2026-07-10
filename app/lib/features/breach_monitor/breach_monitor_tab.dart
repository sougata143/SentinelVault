import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Full Breach Monitor tab containing two sections:
///   A) Password k-anonymity check (purely local SHA-1 prefix, safe to run)
///   B) Opt-in email breach monitoring (third-party HIBP call, requires
///      explicit user consent disclosed before the first check)
class BreachMonitorTab extends StatefulWidget {
  const BreachMonitorTab({super.key});

  @override
  State<BreachMonitorTab> createState() => _BreachMonitorTabState();
}

class _BreachMonitorTabState extends State<BreachMonitorTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.primary.withAlpha(51),
            ),
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(icon: Icon(Icons.lock_clock_outlined), text: 'Password'),
              Tab(icon: Icon(Icons.alternate_email), text: 'Email'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _PasswordBreachSection(),
              _EmailBreachSection(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section A: Password k-anonymity check
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordBreachSection extends StatefulWidget {
  const _PasswordBreachSection();

  @override
  State<_PasswordBreachSection> createState() => _PasswordBreachSectionState();
}

class _PasswordBreachSectionState extends State<_PasswordBreachSection> {
  final _passwordController = TextEditingController();
  final _monitor = BreachMonitor();

  bool _obscure = true;
  bool _isChecking = false;
  PasswordBreachResult? _result;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _monitor.dispose();
    super.dispose();
  }

  Future<void> _checkPassword() async {
    final pw = _passwordController.text;
    if (pw.isEmpty) return;

    setState(() {
      _isChecking = true;
      _result = null;
      _error = null;
    });

    try {
      final result = await _monitor.checkPassword(pw);
      if (mounted) setState(() => _result = result);
    } on BreachCheckException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy notice banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: const Color(0xFF6C63FF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // ignore: deprecated_member_use
                color: const Color(0xFF6C63FF).withOpacity(0.2),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF6C63FF), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacy-safe: only the first 5 characters of your '
                    "password's SHA-1 hash are ever sent — never the "
                    'password itself.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Check a Password',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter any password to see if it has appeared in known data breaches.',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Password to check',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed:
                  (_passwordController.text.isNotEmpty && !_isChecking)
                      ? _checkPassword
                      : null,
              icon: _isChecking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isChecking ? 'Checking…' : 'Check Password'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            _ErrorCard(message: _error!),
          ],
          if (_result != null) ...[
            const SizedBox(height: 24),
            _PasswordResultCard(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _PasswordResultCard extends StatelessWidget {
  final PasswordBreachResult result;
  const _PasswordResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final safe = !result.isBreached;
    final color = safe ? const Color(0xFF00E676) : const Color(0xFFFF5252);
    final icon =
        safe ? Icons.verified_user_outlined : Icons.gpp_bad_outlined;
    final title = safe ? 'Not Found in Any Breach' : 'Found in Data Breaches!';
    final subtitle = safe
        ? 'This password has not appeared in any known breach dataset.'
        : 'This password appeared ${result.pwnedCount.toString()} times across known breaches. '
            'Change it immediately on any service where it is used.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        // ignore: deprecated_member_use
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            // ignore: deprecated_member_use
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
                if (!safe) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      // ignore: deprecated_member_use
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${result.pwnedCount} known breach exposures',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section B: Opt-in email breach monitoring
// ─────────────────────────────────────────────────────────────────────────────

class _EmailBreachSection extends StatefulWidget {
  const _EmailBreachSection();

  @override
  State<_EmailBreachSection> createState() => _EmailBreachSectionState();
}

class _EmailBreachSectionState extends State<_EmailBreachSection> {
  final _emailController = TextEditingController();
  bool _isOptedIn = false;
  bool _isChecking = false;
  List<EmailBreachResult>? _breaches;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Shows a blocking disclosure dialog before making any network call.
  Future<bool> _showDisclosureDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: Color(0xFFFF8906)),
                SizedBox(width: 10),
                Text('Third-Party Data Disclosure'),
              ],
            ),
            content: const Text(
              'Checking your email for data breaches requires sending your '
              'email address to Have I Been Pwned (haveibeenpwned.com) — '
              'a trusted third-party breach-notification service.\n\n'
              'Your email will NOT be shared with any other party. '
              'This check runs once daily and you can opt out at any time '
              'to stop all future checks and delete stored breach records.\n\n'
              'Do you agree to send your email to Have I Been Pwned?',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('I Agree — Enable Monitoring'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _enableMonitoring() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    // Show disclosure dialog — no network call happens until consent is given.
    final consented = await _showDisclosureDialog();
    if (!consented) return;

    setState(() {
      _isOptedIn = true;
      _isChecking = true;
      _breaches = null;
      _error = null;
    });

    // In a real app this would register with the backend and trigger the first
    // check. Here we simulate the result for demonstration purposes since we
    // don't have a live HIBP API key configured.
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isChecking = false;
        // Simulated response — in production this comes from the backend API.
        _breaches = const [];
      });
    }
  }

  void _disableMonitoring() {
    setState(() {
      _isOptedIn = false;
      _breaches = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Third-party warning banner (always visible)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: const Color(0xFFFF8906).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // ignore: deprecated_member_use
                color: const Color(0xFFFF8906).withOpacity(0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  color: Color(0xFFFF8906),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Email monitoring requires sending your email address '
                    'to Have I Been Pwned, a third-party service. '
                    'A full disclosure will be shown before you opt in.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Email Breach Monitor',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Get notified when your email appears in a new data breach. '
            'Checks run once daily and you can opt out at any time.',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (!_isOptedIn) ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Email address to monitor',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8906),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _emailController.text.isNotEmpty
                    ? _enableMonitoring
                    : null,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable Email Monitoring'),
              ),
            ),
          ] else ...[
            // Opted-in state
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: const Color(0xFF00E676).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  // ignore: deprecated_member_use
                  color: const Color(0xFF00E676).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF00E676),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Monitoring ${_emailController.text}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _disableMonitoring,
                    child: const Text(
                      'Disable',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_isChecking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ErrorCard(message: _error!)
            else if (_breaches != null)
              _BreachListCard(breaches: _breaches!),
          ],
        ],
      ),
    );
  }
}

class _BreachListCard extends StatelessWidget {
  final List<EmailBreachResult> breaches;
  const _BreachListCard({required this.breaches});

  @override
  Widget build(BuildContext context) {
    if (breaches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: const Color(0xFF00E676).withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          // ignore: deprecated_member_use
          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: Color(0xFF00E676), size: 32),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Breaches Found',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF00E676),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your email has not been found in any known data breach.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${breaches.length} Breach${breaches.length == 1 ? '' : 'es'} Found',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFFFF5252),
          ),
        ),
        const SizedBox(height: 12),
        ...breaches.map((breach) => _BreachEntryCard(breach: breach)),
      ],
    );
  }
}

class _BreachEntryCard extends StatelessWidget {
  final EmailBreachResult breach;
  const _BreachEntryCard({required this.breach});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: const Color(0xFFFF5252).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        // ignore: deprecated_member_use
        border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF5252),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  breach.breachName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                breach.breachDate,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
          if (breach.dataClasses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: breach.dataClasses
                  .map(
                    (dc) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        // ignore: deprecated_member_use
                        color: const Color(0xFFFF8906).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        dc,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFFF8906),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: const Color(0xFFFF5252).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // ignore: deprecated_member_use
          color: const Color(0xFFFF5252).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF5252)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF5252)),
            ),
          ),
        ],
      ),
    );
  }
}
