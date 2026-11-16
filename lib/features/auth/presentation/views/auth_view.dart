import 'package:auto_route/auto_route.dart';
import 'package:dawarich/core/di/providers/auth_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:dawarich/features/auth/domain/models/auth_qr_payload.dart';
import 'package:dawarich/features/auth/presentation/viewmodels/auth_page_viewmodel.dart';
import 'package:dawarich/features/auth/presentation/widgets/connect_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

@RoutePage()
final class AuthView extends ConsumerWidget {
  const AuthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vmAsync = ref.watch(authPageViewModelProvider);
    return vmAsync.when(
      loading: () => Container(
        decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Container(
        decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: Text(e.toString())),
        ),
      ),
      data: (vm) => provider.ChangeNotifierProvider<AuthPageViewModel>.value(
        value: vm,
        child: _AuthScaffold(vm: vm),
      ),
    );
  }
}

final class _AuthScaffold extends StatelessWidget {
  final AuthPageViewModel vm;

  const _AuthScaffold({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: _AuthFormCard(vm: vm),
          ),
        ),
      ),
    );
  }
}

final class _AuthFormCard extends StatefulWidget {
  final AuthPageViewModel vm;

  const _AuthFormCard({required this.vm});

  @override
  State<_AuthFormCard> createState() => _AuthFormCardState();
}

class _AuthFormCardState extends State<_AuthFormCard> {
  final _hostFormKey = GlobalKey<FormState>();
  final _apiFormKey = GlobalKey<FormState>();
  final _hostedApiFormKey = GlobalKey<FormState>();

  AuthPageViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    vm.addListener(_onVmChanged);
  }

  @override
  void dispose() {
    vm.removeListener(_onVmChanged);
    super.dispose();
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ConnectHeader(vm: vm),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ModeSelector(
                hostedMode: vm.hostedMode,
                onChanged: vm.setHostedMode,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: vm.hostedMode
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _HostedBody(
                        key: const ValueKey('hosted'),
                        vm: vm,
                        formKey: _hostedApiFormKey,
                        onSignIn: () => _handleHostedSignIn(context),
                      ),
                    )
                  : _SelfHostedBody(
                      key: const ValueKey('selfhosted'),
                      vm: vm,
                      hostFormKey: _hostFormKey,
                      apiFormKey: _apiFormKey,
                      onContinue: () => _handleSelfHostedContinue(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleHostedSignIn(BuildContext context) async {
    if (!(_hostedApiFormKey.currentState?.validate() ?? false)) return;

    final ok = await vm.tryLoginHosted(vm.apiKeyController.text.trim());
    if (!ok) return;

    await vm.refreshServerCompatibility();
    if (context.mounted) {
      context.router.root.replaceAll([const PermissionsOnboardingRoute()]);
    }
  }

  Future<void> _handleSelfHostedContinue(BuildContext context) async {
    if (vm.currentStep == 0) {
      if (!(_hostFormKey.currentState?.validate() ?? false)) return;
      final ok = await vm.testHost(vm.hostController.text.trim());
      if (ok) vm.goToNextStep();
      return;
    }

    if (vm.currentStep == 1) {
      final host = vm.hostController.text.trim();
      if (host.isEmpty) {
        vm.setCurrentStep(0);
        vm.setSnackbarMessage('Please set a server first.');
        return;
      }
    }

    if (!(_apiFormKey.currentState?.validate() ?? false)) return;

    final ok = await vm.tryLoginApiKey(vm.apiKeyController.text.trim());
    if (!ok) return;

    await vm.refreshServerCompatibility();
    if (context.mounted) {
      context.router.root.replaceAll([const PermissionsOnboardingRoute()]);
    }
  }
}

// ─── Mode Selector ───────────────────────────────────────────────────────────

final class _ModeSelector extends StatelessWidget {
  final bool hostedMode;
  final ValueChanged<bool> onChanged;

  const _ModeSelector({required this.hostedMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: true,
          label: Text('Hosted'),
          icon: Icon(Icons.cloud_outlined),
        ),
        ButtonSegment<bool>(
          value: false,
          label: Text('Self-hosted'),
          icon: Icon(Icons.dns_outlined),
        ),
      ],
      selected: {hostedMode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        visualDensity: VisualDensity.comfortable,
        side: WidgetStatePropertyAll(
          BorderSide(color: theme.colorScheme.outline.withAlpha(80)),
        ),
      ),
    );
  }
}

// ─── Hosted Body ─────────────────────────────────────────────────────────────

final class _HostedBody extends StatelessWidget {
  final AuthPageViewModel vm;
  final GlobalKey<FormState> formKey;
  final VoidCallback onSignIn;

  const _HostedBody({
    super.key,
    required this.vm,
    required this.formKey,
    required this.onSignIn,
  });

  Future<void> _scanQr(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final String? qrResult =
        await context.router.push<String>(const AuthQrScanRoute());
    if (qrResult == null) return;

    // Try full payload first ({"server_url":…,"api_key":…}),
    // then fall back to treating the raw string as an API key.
    String apiKey;
    try {
      final payload = AuthQrPayload.fromJsonString(qrResult.trim());
      apiKey = payload.apiKey;
    } on FormatException {
      apiKey = qrResult.trim();
    }

    vm.setApiKey(apiKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = vm.isVerifyingHost || vm.isLoggingIn;

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Subtle hosted-instance badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  AuthPageViewModel.hostedUrl.replaceFirst('https://', ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Enter the API key from your Dawarich account.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: vm.apiKeyController,
            obscureText: !vm.apiKeyVisible,
            decoration: InputDecoration(
              labelText: 'API Key',
              prefixIcon: const Icon(Icons.vpn_key),
              filled: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Scan QR',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: busy ? null : () => _scanQr(context),
                  ),
                  IconButton(
                    icon: Icon(vm.apiKeyVisible
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () => vm.setApiKeyVisibility(!vm.apiKeyVisible),
                  ),
                ],
              ),
            ),
            validator: (v) =>
                (v != null && v.isNotEmpty) ? null : 'Enter your API key',
          ),
          if (vm.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                vm.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: busy ? null : onSignIn,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Self-hosted Body ────────────────────────────────────────────────────────

final class _SelfHostedBody extends StatelessWidget {
  final AuthPageViewModel vm;
  final GlobalKey<FormState> hostFormKey;
  final GlobalKey<FormState> apiFormKey;
  final VoidCallback onContinue;

  const _SelfHostedBody({
    super.key,
    required this.vm,
    required this.hostFormKey,
    required this.apiFormKey,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final busy = vm.isVerifyingHost || vm.isLoggingIn;
    final isLast = vm.currentStep == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stepper(
          physics: const ClampingScrollPhysics(),
          currentStep: vm.currentStep,
          onStepContinue: onContinue,
          onStepCancel:
              vm.currentStep > 0 ? () => vm.goToPreviousStep() : null,
          controlsBuilder: (ctx, details) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                if (vm.currentStep > 0)
                  TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back')),
                const Spacer(),
                ElevatedButton(
                  onPressed: busy ? null : details.onStepContinue,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(isLast ? 'Sign in' : 'Next'),
                ),
              ],
            ),
          ),
          steps: [
            Step(
              title: const Text('Server'),
              isActive: vm.currentStep >= 0,
              state: vm.currentStep > 0
                  ? StepState.complete
                  : StepState.indexed,
              content: ServerStepWidget(formKey: hostFormKey),
            ),
            Step(
              title: const Text('Login'),
              isActive: vm.currentStep >= 1,
              state: vm.currentStep > 1
                  ? StepState.complete
                  : StepState.indexed,
              content: LoginStepWidget(formKey: apiFormKey),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Connect Header ──────────────────────────────────────────────────────────

final class _ConnectHeader extends StatelessWidget {
  final AuthPageViewModel vm;

  const _ConnectHeader({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: CircleAvatar(
            key: ValueKey(vm.hostVerified),
            backgroundColor: Theme.of(context).colorScheme.primary,
            radius: 36,
            child: Icon(
              vm.hostVerified ? Icons.cloud_done : Icons.cloud,
              size: 36,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Connect to Dawarich',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }
}