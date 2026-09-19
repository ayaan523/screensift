import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenshot_detect/flutter_screenshot_detect.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/native_screenshot_source.dart';
import 'data/datasources/settings_store.dart';
import 'data/models/processing_status.dart';
import 'data/models/sift_capture.dart';
import 'data/models/sift_category.dart';
import 'data/models/sift_intent.dart';
import 'data/repositories/capture_repository.dart';
import 'data/services/action_dispatcher.dart' as actions;
import 'data/services/image_text_reader.dart';
import 'data/services/notification_service.dart';
import 'data/services/remote_extractor.dart';
import 'data/services/rule_based_extractor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore.withPrefs(prefs);
  final notifications = NotificationService();
  await notifications.init();

  late final CaptureRepository repository;
  repository = CaptureRepository(
    native: NativeScreenshotSource(),
    settings: settings,
    prefs: prefs,
    onCaptureReady: notifications.showAction,
    buildExtractor: () {
      if (settings.canUseRemoteExtractor) {
        return RemoteExtractor(
          endpoint: settings.remoteEndpoint,
          apiKey: settings.remoteApiKey,
        );
      }
      return RuleBasedExtractor(reader: MlKitTextReader());
    },
  );
  unawaited(repository.init());

  runApp(ScreenSiftApp(repository: repository, settings: settings));
}

class ScreenSiftApp extends StatelessWidget {
  const ScreenSiftApp({
    super.key,
    required this.repository,
    required this.settings,
  });

  final CaptureRepository repository;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScreenSift',
      theme: AppTheme.light(),
      home: MainNavigationShell(repository: repository, settings: settings),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({
    super.key,
    required this.repository,
    required this.settings,
  });

  final CaptureRepository repository;
  final SettingsStore settings;

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;
  StreamSubscription<FlutterScreenshotEvent>? _pluginScreenshotSubscription;

  @override
  void initState() {
    super.initState();
    _pluginScreenshotSubscription = FlutterScreenshotDetect().onScreenshot
        .listen((event) {
          final path = event.path;
          if (path != null && path.isNotEmpty) {
            unawaited(widget.repository.importFile(path));
          }
        });
  }

  @override
  void dispose() {
    _pluginScreenshotSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.repository,
        widget.settings,
      ]),
      builder: (context, _) {
        return Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: AppPalette.canvasGradient,
            ),
            child: SafeArea(
              child: IndexedStack(
                index: _index,
                children: <Widget>[
                  VaultScreen(repository: widget.repository),
                  ActionHubScreen(repository: widget.repository),
                  SettingsScreen(
                    repository: widget.repository,
                    settings: widget.settings,
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (value) => setState(() => _index = value),
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_rounded),
                label: 'Vault',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bolt_rounded),
                label: 'Action Hub',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key, required this.repository});

  final CaptureRepository repository;

  @override
  Widget build(BuildContext context) {
    final captures = repository.visible.isEmpty
        ? _demoCaptures
        : repository.visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Header(
          title: 'ScreenSift',
          subtitle: repository.isProcessing
              ? 'Extracting screenshot intent...'
              : 'Smart screenshot vault',
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
            children: <Widget>[
              for (final category in <SiftCategory>[
                SiftCategory.all,
                SiftCategory.academics,
                SiftCategory.finance,
                SiftCategory.personal,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category.label),
                    selected: repository.category == category,
                    onSelected: (_) => repository.setCategory(category),
                  ),
                ),
              FilterChip(
                label: const Text('Processed'),
                selected: repository.onlyActionable,
                onSelected: (_) => repository.toggleOnlyActionable(),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(AppTheme.gutter),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: captures.length,
            itemBuilder: (context, index) => CaptureCard(
              capture: captures[index],
              onTap: () => _showCaptureSheet(context, captures[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class CaptureCard extends StatelessWidget {
  const CaptureCard({super.key, required this.capture, required this.onTap});

  final SiftCapture capture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = capture.cachedPath == null ? null : File(capture.cachedPath!);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppPalette.canvasAlt,
                child: file != null && file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : Icon(
                        _icon(capture.intent),
                        size: 44,
                        color: AppPalette.slateFaint,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    capture.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      _Badge(status: capture.status),
                      const Spacer(),
                      Text(
                        capture.timeLabel,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: capture.tags
                        .take(2)
                        .map((tag) => _Tag(tag))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(SiftIntent intent) => switch (intent) {
    SiftIntent.payment => Icons.payments_rounded,
    SiftIntent.event => Icons.event_rounded,
    SiftIntent.reminder => Icons.task_alt_rounded,
    SiftIntent.link => Icons.link_rounded,
    _ => Icons.image_rounded,
  };
}

class ActionHubScreen extends StatelessWidget {
  const ActionHubScreen({super.key, required this.repository});

  final CaptureRepository repository;

  @override
  Widget build(BuildContext context) {
    final actionable = repository.all.where((c) => c.isActionable).toList();
    final captures = actionable.isEmpty
        ? _demoCaptures.where((c) => c.isActionable).toList()
        : actionable;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Header(
            title: 'Action Hub',
            subtitle: 'One-tap follow-through',
          ),
          const TabBar(
            tabs: <Widget>[
              Tab(text: 'Timetable'),
              Tab(text: 'To-Do'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                ListView(
                  padding: const EdgeInsets.all(AppTheme.gutter),
                  children: captures
                      .where((c) => c.dueAt != null)
                      .map((c) => _TimelineTile(capture: c))
                      .toList(),
                ),
                ListView(
                  padding: const EdgeInsets.all(AppTheme.gutter),
                  children: captures
                      .map((c) => _ActionTile(capture: c))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final CaptureRepository repository;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.gutter),
      children: <Widget>[
        const _Header(
          title: 'Settings',
          subtitle: 'Capture and storage controls',
          compact: true,
        ),
        FilledButton.icon(
          onPressed: () async {
            final file = await ImagePicker().pickImage(
              source: ImageSource.gallery,
            );
            if (file != null) await repository.importFile(file.path);
          },
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Manual Upload'),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          title: const Text('Background Watcher'),
          subtitle: const Text('Auto-detect Android screenshots'),
          value: settings.watchEnabled,
          onChanged: repository.setWatchEnabled,
        ),
        SwitchListTile(
          title: const Text('Auto-Trash'),
          subtitle: const Text('Delete original screenshots after extraction'),
          value: settings.autoTrash,
          onChanged: (value) => settings.autoTrash = value,
        ),
        SwitchListTile(
          title: const Text('Action Notifications'),
          subtitle: const Text('Show heads-up payment and calendar actions'),
          value: settings.notifyOnCapture,
          onChanged: (value) => settings.notifyOnCapture = value,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.capture});

  final SiftCapture capture;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppPalette.tealTint,
          child: Icon(_icon, color: AppPalette.tealDeep),
        ),
        title: Text(
          capture.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(capture.amountLabel ?? capture.relativeLabel),
        trailing: ElevatedButton(
          onPressed: () => _runAction(context, capture),
          child: Text(_label),
        ),
      ),
    );
  }

  IconData get _icon => capture.intent == SiftIntent.payment
      ? Icons.payments_rounded
      : Icons.event_rounded;
  String get _label => capture.intent == SiftIntent.payment ? 'Pay' : 'Sync';
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.capture});

  final SiftCapture capture;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            capture.timeLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(
            color: AppPalette.teal,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    capture.displayTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (capture.summary != null)
                    Text(
                      capture.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _showCaptureSheet(BuildContext context, SiftCapture capture) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            capture.displayTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _DataRow(label: 'Intent', value: capture.intent.label),
          _DataRow(label: 'Category', value: capture.category.label),
          if (capture.summary != null)
            _DataRow(label: 'Summary', value: capture.summary!),
          if (capture.upiId != null)
            _DataRow(label: 'UPI', value: capture.upiId!),
          if (capture.amountLabel != null)
            _DataRow(label: 'Amount', value: capture.amountLabel!),
          if (capture.dueAt != null)
            _DataRow(label: 'Date', value: capture.dueAt!.toString()),
          const SizedBox(height: 16),
          if (capture.isActionable)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _runAction(context, capture),
                child: Text(_actionLabel(capture)),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _runAction(BuildContext context, SiftCapture capture) async {
  const dispatcher = actions.ActionDispatcher();
  final outcome = switch (capture.intent) {
    SiftIntent.payment => await dispatcher.pay(capture),
    SiftIntent.event ||
    SiftIntent.reminder => await dispatcher.schedule(capture),
    SiftIntent.link => await dispatcher.openLink(capture),
    _ => actions.ActionOutcome.unsupported,
  };
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == actions.ActionOutcome.done
              ? 'Action opened'
              : 'No app found for this action',
        ),
      ),
    );
  }
}

String _actionLabel(SiftCapture capture) => switch (capture.intent) {
  SiftIntent.payment => 'Pay Now via UPI',
  SiftIntent.event || SiftIntent.reminder => 'Sync Calendar',
  SiftIntent.link => 'Open Link',
  _ => 'Open',
};

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 0 : 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppPalette.slateMuted),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});

  final ProcessingStatus status;

  @override
  Widget build(BuildContext context) {
    final ready = status.isReady;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ready ? AppPalette.successTint : AppPalette.warningTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ready ? 'Ready' : 'Processing',
        style: TextStyle(
          color: ready ? AppPalette.success : AppPalette.warning,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.slateMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

final List<SiftCapture> _demoCaptures = <SiftCapture>[
  SiftCapture(
    id: 1,
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    name: 'upi_payment.png',
    status: ProcessingStatus.ready,
    category: SiftCategory.finance,
    intent: SiftIntent.payment,
    title: 'Pay Rahul for dinner',
    summary: 'UPI request extracted from screenshot.',
    amount: 450,
    upiId: 'rahul@okhdfcbank',
    payeeName: 'Rahul',
    tags: const <String>['Money', 'Payment'],
    confidence: 0.94,
  ),
  SiftCapture(
    id: 2,
    createdAt: DateTime.now().add(const Duration(hours: 6)),
    name: 'hackathon_schedule.png',
    status: ProcessingStatus.ready,
    category: SiftCategory.academics,
    intent: SiftIntent.event,
    title: 'AWS Bharat Build checkpoint',
    summary: 'Demo rehearsal and submission checkpoint.',
    dueAt: DateTime.now().add(const Duration(hours: 6)),
    tags: const <String>['School', 'Event'],
    confidence: 0.91,
  ),
  SiftCapture(
    id: 3,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    name: 'vtu_syllabus.png',
    status: ProcessingStatus.ready,
    category: SiftCategory.academics,
    intent: SiftIntent.document,
    title: 'VTU Syllabus: Module 1',
    summary: 'Academic screenshot grouped as a document.',
    tags: const <String>['School', 'Document'],
    confidence: 0.82,
  ),
  SiftCapture(
    id: 4,
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    name: 'order_tracking.png',
    status: ProcessingStatus.ready,
    category: SiftCategory.shopping,
    intent: SiftIntent.tracking,
    title: 'Amazon delivery update',
    summary: 'Package status and order reference captured.',
    referenceCode: 'OD42891',
    tags: const <String>['Shopping', 'Tracking'],
    confidence: 0.86,
  ),
];
