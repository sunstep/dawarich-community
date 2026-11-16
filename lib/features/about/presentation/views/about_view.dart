import 'package:auto_route/auto_route.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
final class AboutView extends StatefulWidget {
  const AboutView({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(gradient: theme.pageBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.router.maybePop(),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── App icon ──
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    radius: 44,
                    child: Icon(
                      Icons.pin_drop,
                      size: 44,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── App name ──
                  Text(
                    'Dawarich',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ── Version ──
                  if (_packageInfo != null)
                    Text(
                      'v${_packageInfo!.version} (${_packageInfo!.buildNumber})',
                      style: theme.textTheme.bodySmall,
                    ),

                  const SizedBox(height: 28),

                  // ── Community disclaimer card ──
                  _InfoCard(
                    icon: Icons.people_outline,
                    title: 'Community Project',
                    body: 'This is an unofficial community-built companion app '
                        'for the Dawarich self-hosted location tracker. It is '
                        'not affiliated with, endorsed by, or maintained by the '
                        'official Dawarich project or its maintainer.',
                  ),
                  const SizedBox(height: 12),

                  // ── GitHub card ──
                  _InfoCard(
                    icon: Icons.code,
                    title: 'Open Source',
                    body: 'This app is open source. Contributions, bug reports, '
                        'and feature requests are welcome.',
                    action: _LinkButton(
                      label: 'View on GitHub',
                      url: 'https://github.com/sunstep/dawarich-android',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Server project card ──
                  _InfoCard(
                    icon: Icons.dns_outlined,
                    title: 'Dawarich Server',
                    body: 'The Dawarich server is a self-hosted location '
                        'history solution developed and maintained by Freika.',
                    action: _LinkButton(
                      label: 'Official Dawarich Project',
                      url: 'https://github.com/Freika/dawarich',
                    ),
                  ),

                  const SizedBox(height: 32),

                  if (kDebugMode) ...[
                    _InfoCard(
                      icon: Icons.bug_report_outlined,
                      title: 'Developer Tools',
                      body: 'Inspect Tracelet tracking diagnostics, '
                          'foreground service health, permissions and logs.',
                      action: OutlinedButton.icon(
                        onPressed: () => TraceletDoctor.show(context),
                        icon: const Icon(Icons.medical_services_outlined),
                        label: const Text('Open Tracelet Doctor'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Subtle footer ──
                  Text(
                    'Made with ❤️ by Sunstep, for the community',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: theme.colorScheme.secondary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

final class _LinkButton extends StatelessWidget {
  final String label;
  final String url;

  const _LinkButton({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _openUrl(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_new,
              size: 16,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}




