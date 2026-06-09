import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:dawarich/core/di/providers/viewmodel_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/core/shell/drawer/drawer.dart';
import 'package:dawarich/core/theme/app_gradients.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:dawarich/features/tracking/presentation/models/tracker_page_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:option_result/option_result.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@RoutePage()
final class TrackerView extends ConsumerWidget {
  const TrackerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vmAsync = ref.watch(trackerPageViewModelProvider);

    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).pageBackground),
      child: vmAsync.when(
        loading: () => AppScaffold(
          title: 'Tracker',
          titleFontSize: 32,
          appBarBackgroundColor: Colors.transparent,
          scaffoldBackgroundColor: Colors.transparent,
          drawer: CustomDrawer(),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => AppScaffold(
          title: 'Tracker',
          titleFontSize: 32,
          appBarBackgroundColor: Colors.transparent,
          scaffoldBackgroundColor: Colors.transparent,
          drawer: CustomDrawer(),
          body: Center(child: Text(e.toString())),
        ),
        data: (vm) {
          return ChangeNotifierProvider.value(
            value: vm,
            child: AppScaffold(
              title: 'Tracker',
              titleFontSize: 32,
              appBarBackgroundColor: Colors.transparent,
              scaffoldBackgroundColor: Colors.transparent,
              drawer: CustomDrawer(),
              body: _TrackerViewContentBody(),
            ),
          );
        },
      ),
    );
  }
}

/// Everything below expects to read the VM via provider's `context.watch`.
/// This widget is the original tracker page content entry-point.
final class _TrackerViewContentBody extends StatefulWidget {
  @override
  State<_TrackerViewContentBody> createState() =>
      _TrackerViewContentBodyState();
}

class _TrackerViewContentBodyState extends State<_TrackerViewContentBody> {
  StreamSubscription<String>? _consentSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Subscribe to consent prompt stream (only once)
    _consentSub ??=
        context.read<TrackerPageViewModel>().onConsentPrompt.listen((message) {
      if (!mounted) return;
      _showConsentDialog(message);
    });
  }

  @override
  void dispose() {
    _consentSub?.cancel();
    super.dispose();
  }

  void _showConsentDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              context.read<TrackerPageViewModel>().handleConsentResponse(false);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<TrackerPageViewModel>().handleConsentResponse(true);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: const [
            LastPointCard(),
            _SettingsCard(),
          ],
        ),
      ),
    );
  }
}

class LastPointCard extends StatelessWidget {
  const LastPointCard({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final accent = Theme.of(context).colorScheme.secondary;
    final theme = Theme.of(context);
    final white = theme.colorScheme.onSurface;
    final white70 = white.withValues(alpha: 0.7);

    final isExpanded = !vm.hideLastPoint;

    // helper for each info row
    Widget tile(IconData icon, String label, String value) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: white),
        title: Text(label, style: TextStyle(color: white70)),
        trailing: Text(value,
            style: TextStyle(color: white, fontWeight: FontWeight.bold)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Card(
        color: Theme.of(context).cardColor,
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // — Header with tap to expand/collapse —
            InkWell(
              onTap: () => vm.setHideLastPoint(!vm.hideLastPoint),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                          child: Text(
                        'Last Point',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall!
                            .copyWith(
                                color: white, fontWeight: FontWeight.bold),
                      )),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: white70,
                    ),
                  ],
                ),
              ),
            ),

            // — Animated body —
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Divider(color: Theme.of(context).dividerColor),
                    const SizedBox(height: 16),

                    // info rows
                    tile(
                      Icons.access_time,
                      'Time',
                      vm.lastPoint?.formattedTimestamp ?? '—',
                    ),
                    tile(
                      Icons.format_list_numbered,
                      'Batch Size',
                      vm.batchPointCount.toString(),
                    ),
                    tile(
                      Icons.my_location,
                      'Latitude',
                      vm.lastPoint?.latitude.toStringAsFixed(5) ?? '—',
                    ),
                    tile(
                      Icons.my_location,
                      'Longitude',
                      vm.lastPoint?.longitude.toStringAsFixed(5) ?? '—',
                    ),

                    const SizedBox(height: 24),

                    // action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accent),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: vm.isTracking
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  )
                                : Icon(Icons.add_location_alt, color: accent),
                            label: Text('Track Point',
                                style: TextStyle(color: white)),
                            onPressed: vm.isTracking
                                ? null
                                : () async {
                                    await handleManualPointRequest(context, vm);
                                  },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.view_list),
                            label: const Text('View Batch'),
                            onPressed: () => context.router.root
                                .push(const BatchExplorerRoute()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> handleManualPointRequest(
      BuildContext context, TrackerPageViewModel vm) async {
    if (vm.isTrackingAutomatically) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Manual Tracking Disabled'),
          content: const Text(
            'Manual tracking is disabled while automatic tracking is active. '
            'Please stop automatic tracking first if you want to manually add a point.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await vm.trackPoint();
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late PageController _pageController;
  int _currentPage = 0;
  static const int _pageCount = 6;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.cardColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          if (isDark)
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 40,
              spreadRadius: -10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page content
          SizedBox(
            height: 320,
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              children: const [
                _TrackingHeroPage(),
                _FrequencyPage(),
                _MinimumPointDistancePage(),
                _BatchingPage(),
                _BatchExpirationPage(),
                _AdvancedPage(),
                _TrackRecordingPage(),
              ],
            ),
          ),
          // Dot indicators with consistent background
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (index) {
                final isActive = index == _currentPage;
                return GestureDetector(
                  onTap: () => _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 1: Hero tracking card - the main feature
class _TrackingHeroPage extends StatelessWidget {
  const _TrackingHeroPage();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);
    final isActive = vm.isTrackingAutomatically;
    final isLoading = vm.isUpdatingTracking;

    return InkWell(
      onTap: isLoading
          ? null
          : () async {
              final result = await vm.toggleAutomaticTracking(!isActive);
              if (!context.mounted) return;
              if (result case Err(value: final message)) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Tracking Setup Failed"),
                    content: Text(message),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              }
            },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status icon with glow effect when active
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    isActive ? Icons.location_on : Icons.location_off,
                    size: 40,
                    color: isActive
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // Status text
            Text(
              isActive ? 'Tracking Active' : 'Tracking Inactive',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isActive
                  ? 'Your location is being recorded'
                  : 'Tap to start tracking',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Swipe hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Swipe for settings',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_circle_left_rounded,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 2: Frequency settings
class _FrequencyPage extends StatefulWidget {
  const _FrequencyPage();

  @override
  State<_FrequencyPage> createState() => _FrequencyPageState();
}

class _FrequencyPageState extends State<_FrequencyPage> {
  late TextEditingController _frequencyController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _frequencyController = TextEditingController();
  }

  @override
  void dispose() {
    _frequencyController.dispose();
    super.dispose();
  }

  void _applyFrequency(TrackerPageViewModel vm) {
    final parsed = int.tryParse(_frequencyController.text);
    if (parsed != null && parsed >= 0) {
      vm.setTrackingFrequency(parsed);
      _frequencyController.text = parsed.toString();
    }
    FocusScope.of(context).unfocus();
  }

  String _formatFrequency(int seconds) {
    if (seconds == 0) return 'Auto';
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);

    if (!_initialized) {
      _frequencyController.text = vm.trackingFrequency.toString();
      _initialized = true;
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Frequency',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current: ${_formatFrequency(vm.trackingFrequency)}',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How often to record your location',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _frequencyController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Seconds (0 = auto)',
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _applyFrequency(vm),
              onEditingComplete: () => _applyFrequency(vm),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 3: Minimum Point Distance
class _MinimumPointDistancePage extends StatefulWidget {
  const _MinimumPointDistancePage();

  @override
  State<_MinimumPointDistancePage> createState() => _MinimumPointDistancePageState();
}

class _MinimumPointDistancePageState extends State<_MinimumPointDistancePage> {
  late TextEditingController _minPointDistController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _minPointDistController = TextEditingController();
  }

  @override
  void dispose() {
    _minPointDistController.dispose();
    super.dispose();
  }

  void _applyMinimumPointDistance(TrackerPageViewModel vm) {
    final parsed = int.tryParse(_minPointDistController.text);
    if (parsed != null && parsed >= 0) {
      vm.setMinimumPointDistance(parsed);
      _minPointDistController.text = parsed.toString();
    }
    FocusScope.of(context).unfocus();
  }

  String _formatMinimumPointDistance(int distance) {
    return '${distance}m';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);

    if (!_initialized) {
      _minPointDistController.text = vm.minimumPointDistance.toString();
      _initialized = true;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.social_distance,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Minimum Point Distance',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current: ${_formatMinimumPointDistance(vm.minimumPointDistance)}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Minimum distance between recorded points, also affects frequency when set to auto',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _minPointDistController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Meters',
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => _applyMinimumPointDistance(vm),
                        onEditingComplete: () => _applyMinimumPointDistance(vm),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Page 4: Batching settings
class _BatchingPage extends StatefulWidget {
  const _BatchingPage();

  @override
  State<_BatchingPage> createState() => _BatchingPageState();
}

class _BatchingPageState extends State<_BatchingPage> {
  late TextEditingController _batchController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _batchController = TextEditingController();
  }

  @override
  void dispose() {
    _batchController.dispose();
    super.dispose();
  }

  void _applyBatch(TrackerPageViewModel vm) {
    final parsed = int.tryParse(_batchController.text);
    if (parsed != null) {
      vm.setMaxPointsPerBatch(parsed.clamp(vm.minBatch, vm.maxBatch));
      _batchController.text = vm.maxPointsPerBatch.toString();
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);

    if (!_initialized) {
      _batchController.text = vm.maxPointsPerBatch.toString();
      _initialized = true;
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.layers,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Batching',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current: ${vm.maxPointsPerBatch} points',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Points to collect before uploading',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _batchController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${vm.minBatch}–${vm.maxBatch}',
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _applyBatch(vm),
              onEditingComplete: () => _applyBatch(vm),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 5: Batch expiration (time-based upload trigger)
class _BatchExpirationPage extends StatelessWidget {
  const _BatchExpirationPage();

  static const _options = <int?, String>{
    null: 'Off',
    15: '15m',
    30: '30m',
    60: '1h',
    120: '2h',
    360: '6h',
    720: '12h',
    1440: '24h',
  };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);
    final current = vm.batchExpirationMinutes;
    final isEnabled = current != null && current > 0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              isEnabled ? Icons.hourglass_bottom_rounded : Icons.hourglass_disabled_rounded,
              key: ValueKey(isEnabled),
              size: 48,
              color: isEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Batch Expiration',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isEnabled
                ? 'Upload after ${_options[current] ?? '${current}m'} of inactivity'
                : 'Only upload when batch is full',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _options.entries.map((e) {
              final isSelected = e.key == current;
              final isOff = e.key == null;
              return ChoiceChip(
                label: Text(
                  e.value,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : isOff
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => vm.setBatchExpirationMinutes(e.key),
                selectedColor: isOff
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Page 6: Advanced settings
class _AdvancedPage extends StatefulWidget {
  const _AdvancedPage();

  @override
  State<_AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<_AdvancedPage> {
  late TextEditingController _distanceController;
  late TextEditingController _deviceIdController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _distanceController = TextEditingController();
    _deviceIdController = TextEditingController();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  void _applyDeviceId(TrackerPageViewModel vm) {
    final text = _deviceIdController.text.trim();
    if (text.isNotEmpty) {
      vm.setDeviceId(text);
    }
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);

    if (!_initialized) {
      _distanceController.text = vm.minimumPointDistance.toString();
      _deviceIdController.text = vm.deviceId;
      _initialized = true;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.tune,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Advanced',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // Accuracy dropdown
          Row(
            children: [
              const Icon(Icons.precision_manufacturing, size: 18),
              const SizedBox(width: 8),
              Text('Accuracy', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: DropdownButton<LocationPrecision>(
              value: vm.locationAccuracy,
              isExpanded: true,
              onChanged: (v) => v != null ? vm.setLocationAccuracy(v) : null,
              items: vm.accuracyOptions.map((opt) {
                return DropdownMenuItem(
                  value: opt['value'] as LocationPrecision,
                  child: Text(opt['label'] as String),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Device ID
          Row(
            children: [
              const Icon(Icons.perm_device_information, size: 18),
              const SizedBox(width: 8),
              Text('Device ID', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deviceIdController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Device identifier',
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _applyDeviceId(vm),
                  onEditingComplete: () => _applyDeviceId(vm),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () async {
                  await vm.resetDeviceId();
                  _deviceIdController.text = vm.deviceId;
                },
                tooltip: 'Reset',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page 5: Track recording (experimental feature)
class _TrackRecordingPage extends StatelessWidget {
  const _TrackRecordingPage();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrackerPageViewModel>();
    final theme = Theme.of(context);

    return InkWell(
      onTap: vm.toggleRecording,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              vm.isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
              size: 48,
              color: vm.isRecording
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Track Recording',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (vm.isRecording)
              Text(
                'Track: ${vm.currentTrack?.trackId ?? 'Unknown'}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              Text(
                'Gives an additional ID to points to group them together. Tap to start a new track.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Experimental',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      )
    );
  }
}
