import 'package:flutter/material.dart';

import 'catalog.dart';
import 'esim.dart';
import 'esim_detail_api.dart';
import 'esim_setup_screen.dart';
import 'euicc.dart';
import 'purchase_sheet.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _line = Color(0xFFE4E8F0);
const _errorColor = Color(0xFFD14343);
const _successColor = Color(0xFF1E8E5A);
const _barTrack = Color(0xFFE2E8F0);
const _barFill = Color(0xFF0284C7);
const _noteMax = 255;
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Same wording as the web package history.
String formatPackageDate(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) {
    return '—';
  }
  final parsed =
      DateTime.tryParse(value) ??
      DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null) {
    return value;
  }
  final local = parsed.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${_months[local.month - 1]} ${local.day}, ${local.year}, '
      '$hour:$minute $period';
}

String formatDataMb(int mb) {
  if (mb.abs() >= 1024) {
    final gb = (mb / 1024 * 100).round() / 100;
    final text = gb == gb.roundToDouble()
        ? gb.toStringAsFixed(0)
        : gb.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text GB';
  }
  return '$mb MB';
}

String formatPaidAmount(String? paidUsd, String currency) {
  final amount = double.tryParse(paidUsd ?? '');
  if (amount == null) {
    return '—';
  }
  final code = currency.trim().isEmpty ? 'USD' : currency.trim();
  return '\$${amount.toStringAsFixed(2)} $code';
}

String packageSpecLabel(AppliedPackage package) {
  final days = package.validityDays == 1
      ? '1 day'
      : '${package.validityDays} days';
  return '${packageDataName(package)} · $days';
}

String packageDataName(AppliedPackage package) {
  if (package.isUnlimited) {
    return 'Unlimited';
  }
  final data = package.dataAllowance.trim();
  return data.isEmpty ? '—' : data;
}

class EsimDetailScreen extends StatefulWidget {
  const EsimDetailScreen({
    super.key,
    required this.esim,
    this.api = const EsimDetailApi(),
    this.installer,
  });

  final OwnedEsim esim;
  final EsimDetailApi api;
  final EsimInstaller? installer;

  @override
  State<EsimDetailScreen> createState() => _EsimDetailScreenState();
}

class _EsimDetailScreenState extends State<EsimDetailScreen> {
  late final EsimStage _stage = esimStage(widget.esim.status);
  BillingDisplay _display = BillingDisplay.fallback;

  List<AppliedPackage> _packages = const [];
  bool _packagesLoaded = false;
  String? _packagesError;
  EsimUsage? _usage;
  bool _refreshing = false;

  List<TopupOffer> _topups = const [];
  bool _topupsLoaded = false;
  String? _topupsError;
  String? _topupSuccess;

  bool _installing = false;
  String? _installError;

  late final TextEditingController _note = TextEditingController(
    text: widget.esim.note,
  );
  late String _savedNote = widget.esim.note;
  bool _noteSaving = false;
  bool _noteSaved = false;
  String? _noteError;

  int get _esimId => widget.esim.id;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() => _noteSaved = false));
    widget.api.display().then((display) {
      if (mounted) {
        setState(() => _display = display);
      }
    }, onError: (_) {});
    _refreshPackages();
    _loadTopups();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _refreshPackages() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _packagesError = null;
    });
    final packagesFuture = widget.api.packages(_esimId);
    final usageFuture = _stage == EsimStage.inUse
        ? widget.api.usage(_esimId)
        : null;
    try {
      final packages = await packagesFuture;
      if (mounted) {
        setState(() => _packages = packages);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _packagesError = 'Could not load packages.');
      }
    }
    if (usageFuture != null) {
      try {
        final usage = await usageFuture;
        if (mounted) {
          setState(() => _usage = usage);
        }
      } catch (_) {
        // The cached list values still drive the bar.
      }
    }
    if (mounted) {
      setState(() {
        _refreshing = false;
        _packagesLoaded = true;
      });
    }
  }

  Future<void> _loadTopups() async {
    try {
      final topups = await widget.api.topups(_esimId);
      if (!mounted) {
        return;
      }
      setState(() {
        _topups = topups;
        _topupsLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _topupsLoaded = true;
        _topupsError = 'Could not load top-ups.';
      });
    }
  }

  Future<void> _buyTopup(TopupOffer offer) async {
    setState(() => _topupSuccess = null);
    final bought = await showPurchaseSheet(
      context,
      package: offer.toCatalogPackage(),
      display: _display,
      sendOrder: (packageId, key) =>
          widget.api.buyTopup(_esimId, packageId, key),
    );
    if (!mounted || !bought) {
      return;
    }
    setState(() => _topupSuccess = 'Top-up purchased.');
    _refreshPackages();
  }

  Future<void> _install() async {
    final link = esimSetupLink(
      lpa: widget.esim.lpa,
      matchingId: widget.esim.matchingId,
    );
    if (link == null || _installing) {
      return;
    }
    setState(() {
      _installing = true;
      _installError = null;
    });
    String? message;
    try {
      final installer = widget.installer ?? installEsim;
      message = await installer(link);
    } catch (_) {
      message = 'Could not install the eSIM.';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _installing = false;
      _installError = message;
    });
  }

  void _openSetup(EsimSetupView view) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EsimSetupScreen(esim: widget.esim, view: view),
      ),
    );
  }

  Future<void> _saveNote() async {
    final next = _note.text.trim();
    if (_noteSaving || next == _savedNote.trim()) {
      return;
    }
    setState(() {
      _noteSaving = true;
      _noteError = null;
    });
    try {
      final saved = await widget.api.saveNote(_esimId, next);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedNote = saved;
        _noteSaving = false;
        _noteSaved = true;
      });
      if (_note.text != saved) {
        _note.text = saved;
        _noteSaved = true;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _noteSaving = false;
        _noteError = error is DetailApiException
            ? error.message
            : 'Could not save the note.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esim = widget.esim;
    final canInstall =
        esimSetupLink(lpa: esim.lpa, matchingId: esim.matchingId) != null;
    final showPackages =
        _stage != EsimStage.purchased ||
        _packages.isNotEmpty ||
        _packagesError != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/store_background.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: _ink,
                          size: 28,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          esim.destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatEsimStatus(esim.status),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Text(
                          'ICCID: ${esim.iccid}',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_stage == EsimStage.purchased) ...[
                          EsimInstallActions(
                            busy: _installing,
                            canInstall: canInstall,
                            error: _installError,
                            onInstall: _install,
                            onManual: () => _openSetup(EsimSetupView.manual),
                            onQr: () => _openSetup(EsimSetupView.qr),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (showPackages) ...[
                          _PackagesCard(
                            packages: _packages,
                            loaded: _packagesLoaded,
                            error: _packagesError,
                            refreshing: _refreshing,
                            onRefresh: _refreshPackages,
                            usage: _stage == EsimStage.inUse
                                ? _UsageValues.from(esim, _usage)
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _TopupsCard(
                          topups: _topups,
                          loaded: _topupsLoaded,
                          error: _topupsError,
                          success: _topupSuccess,
                          display: _display,
                          onBuy: _buyTopup,
                          renew: _topups.isEmpty
                              ? null
                              : _AutoTopupForm(
                                  esimId: _esimId,
                                  topups: _topups,
                                  api: widget.api,
                                ),
                        ),
                        const SizedBox(height: 16),
                        _NotesCard(
                          controller: _note,
                          saving: _noteSaving,
                          saved: _noteSaved,
                          error: _noteError,
                          dirty: _note.text.trim() != _savedNote.trim(),
                          onSave: _saveNote,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageValues {
  const _UsageValues({
    required this.remainingMb,
    required this.totalMb,
    required this.isUnlimited,
  });

  final int? remainingMb;
  final int? totalMb;
  final bool isUnlimited;

  static _UsageValues from(OwnedEsim esim, EsimUsage? usage) {
    return _UsageValues(
      remainingMb: usage?.remainingMb ?? esim.usageRemainingMb,
      totalMb: usage?.totalMb ?? esim.usageTotalMb,
      isUnlimited: usage?.isUnlimited ?? esim.usageIsUnlimited,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled
          ? (enabled ? _accent : _accent.withValues(alpha: 0.45))
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: filled ? null : Border.all(color: _line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : (enabled ? _ink : _muted),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PackagesCard extends StatelessWidget {
  const _PackagesCard({
    required this.packages,
    required this.loaded,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.usage,
  });

  final List<AppliedPackage> packages;
  final bool loaded;
  final String? error;
  final bool refreshing;
  final VoidCallback onRefresh;

  /// Set only for eSIMs in use; drives the data bar.
  final _UsageValues? usage;

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final p in packages)
        if (p.status == 'active' || p.status == 'not_active') p,
    ];
    final previous = [
      for (final p in packages)
        if (p.status == 'expired' || p.status == 'finished') p,
    ];
    final unknown = [
      for (final p in packages)
        if (!available.contains(p) && !previous.contains(p)) p,
    ];
    final usage = this.usage;

    return _Card(
      children: [
        _CardTitle(
          'Packages',
          subtitle:
              'Track your combined data balance for all packages on this eSIM.',
          trailing: _SmallButton(
            label: refreshing ? 'Refreshing…' : 'Refresh',
            onTap: refreshing ? null : onRefresh,
          ),
        ),
        if (usage != null) ...[
          const SizedBox(height: 14),
          _UsageBar(values: usage),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: _errorColor)),
        ],
        if (!loaded && error == null) ...[
          const SizedBox(height: 12),
          const Text('Loading packages…', style: TextStyle(color: _muted)),
        ] else if (loaded && error == null && packages.isEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'No packages on this eSIM yet.',
            style: TextStyle(color: _muted),
          ),
        ],
        _PackageGroup(title: 'Available packages', packages: available),
        _PackageGroup(title: 'Previous packages', packages: previous),
        _PackageGroup(title: 'Unknown packages', packages: unknown),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.values});

  final _UsageValues values;

  @override
  Widget build(BuildContext context) {
    if (values.isUnlimited) {
      return const Text('Unlimited', style: TextStyle(color: _muted));
    }
    final fraction = remainingDataFraction(
      remainingMb: values.remainingMb,
      totalMb: values.totalMb,
      isUnlimited: values.isUnlimited,
    );
    if (fraction == null) {
      return const Text('Usage not synced', style: TextStyle(color: _muted));
    }
    final remaining = values.remainingMb!;
    final total = values.totalMb!;
    final used = (total - remaining).clamp(0, total);
    final remainingPercent = (remaining / total * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Data left: ${formatDataMb(remaining)} ($remainingPercent%)',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            Text(
              'Data used: ${formatDataMb(used)} (${100 - remainingPercent}%)',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: const Key('esim-usage-bar'),
            value: fraction,
            minHeight: 6,
            color: _barFill,
            backgroundColor: _barTrack,
          ),
        ),
      ],
    );
  }
}

class _PackageGroup extends StatefulWidget {
  const _PackageGroup({required this.title, required this.packages});

  final String title;
  final List<AppliedPackage> packages;

  @override
  State<_PackageGroup> createState() => _PackageGroupState();
}

class _PackageGroupState extends State<_PackageGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    if (widget.packages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Badge(label: '${widget.packages.length}'),
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  color: _muted,
                ),
              ],
            ),
          ),
          if (_open)
            for (final package in widget.packages)
              _PackageRow(package: package),
        ],
      ),
    );
  }
}

class _PackageRow extends StatefulWidget {
  const _PackageRow({required this.package});

  final AppliedPackage package;

  @override
  State<_PackageRow> createState() => _PackageRowState();
}

class _PackageRowState extends State<_PackageRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    final status = switch (package.status) {
      'active' => 'Active',
      'not_active' => 'Not active',
      'expired' || 'finished' => 'Expired',
      _ => 'Unknown',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  color: _muted,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  package.kind == 'esim' ? 'eSIM' : 'Top-up',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: _PackageName(package: package)),
                _Badge(label: status, active: package.status == 'active'),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 6),
              child: Column(
                children: [
                  _DetailLine(
                    'Created on',
                    formatPackageDate(package.createdAt),
                  ),
                  _DetailLine(
                    'Activated on',
                    formatPackageDate(package.activatedAt),
                  ),
                  _DetailLine(
                    'Expires on',
                    formatPackageDate(package.expiresAt),
                  ),
                  _DetailLine(
                    'Amount',
                    formatPaidAmount(package.paidUsd, package.currency),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PackageName extends StatelessWidget {
  const _PackageName({required this.package});

  final AppliedPackage package;

  @override
  Widget build(BuildContext context) {
    final badge = packageExpiryBadge(package);
    final style = const TextStyle(color: _muted, fontSize: 13);
    if (badge == null) {
      return Text(
        packageSpecLabel(package),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            packageDataName(package),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Text(' · ', style: style),
        _ExpiryBadge(badge: badge),
      ],
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({required this.badge});

  final PackageExpiryBadge badge;

  @override
  Widget build(BuildContext context) {
    final color = badge.urgent ? _errorColor : _successColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badge.urgent ? const Color(0xFFFDECEC) : const Color(0xFFE5F6EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE0EEFF) : const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? _accent : _muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TopupsCard extends StatelessWidget {
  const _TopupsCard({
    required this.topups,
    required this.loaded,
    required this.error,
    required this.success,
    required this.display,
    required this.onBuy,
    required this.renew,
  });

  final List<TopupOffer> topups;
  final bool loaded;
  final String? error;
  final String? success;
  final BillingDisplay display;
  final ValueChanged<TopupOffer> onBuy;
  final Widget? renew;

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _CardTitle(
          'Available top-ups',
          subtitle: 'Add more data to this eSIM with your balance.',
        ),
        if (success != null) ...[
          const SizedBox(height: 10),
          Text(
            success!,
            style: const TextStyle(
              color: _successColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (!loaded)
          const Text('Loading top-ups…', style: TextStyle(color: _muted))
        else if (error != null)
          Text(error!, style: const TextStyle(color: _errorColor))
        else if (topups.isEmpty)
          const Text(
            'No top-up packages available.',
            style: TextStyle(color: _muted),
          )
        else
          for (final topup in topups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topup.title,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${topup.isUnlimited ? 'Unlimited' : topup.dataAllowance}'
                          ' · ${validityHeading(topup.validityDays)}',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  _OfferPrice(topup: topup, display: display),
                  const SizedBox(width: 10),
                  _SmallButton(
                    label: 'Buy',
                    filled: true,
                    onTap: () => onBuy(topup),
                  ),
                ],
              ),
            ),
        ?renew,
      ],
    );
  }
}

class _OfferPrice extends StatelessWidget {
  const _OfferPrice({required this.topup, required this.display});

  final TopupOffer topup;
  final BillingDisplay display;

  @override
  Widget build(BuildContext context) {
    final charge = formatCatalogPrice(topup.priceUsd, display);
    final list = struckListPrice(topup.listPriceUsd, topup.priceUsd, display);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (list != null)
          Text(
            list,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
              decorationColor: _muted,
            ),
          ),
        Text(
          charge,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AutoTopupForm extends StatefulWidget {
  const _AutoTopupForm({
    required this.esimId,
    required this.topups,
    required this.api,
  });

  final int esimId;
  final List<TopupOffer> topups;
  final EsimDetailApi api;

  @override
  State<_AutoTopupForm> createState() => _AutoTopupFormState();
}

class _AutoTopupFormState extends State<_AutoTopupForm> {
  AutoTopupPolicy? _policy;
  bool _loading = true;
  String? _unavailable;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  bool _enabled = false;
  String _packageId = '';
  bool _expiry = true;
  bool _remainingData = false;
  String _usageKind = 'threshold';
  String _renewMode = 'until_funds';
  final _threshold = TextEditingController(text: '500');
  final _count = TextEditingController(text: '3');

  @override
  void initState() {
    super.initState();
    _applyPolicy(null);
    _load();
  }

  @override
  void dispose() {
    _threshold.dispose();
    _count.dispose();
    super.dispose();
  }

  void _applyPolicy(AutoTopupPolicy? policy) {
    _policy = policy;
    final fallback = widget.topups.first.id;
    if (policy == null) {
      _enabled = false;
      _packageId = fallback;
      _expiry = true;
      _remainingData = false;
      _usageKind = 'threshold';
      _renewMode = 'until_funds';
      _threshold.text = '500';
      _count.text = '3';
      return;
    }
    _enabled = policy.enabled && policy.status != 'disabled';
    _packageId = policy.packageId.isEmpty ? fallback : policy.packageId;
    _expiry = policy.expiryEnabled;
    _remainingData = policy.usageMode != 'disabled';
    _usageKind = policy.usageMode == 'zero' ? 'zero' : 'threshold';
    _renewMode = policy.renewMode;
    _threshold.text = '${policy.thresholdMb ?? 500}';
    _count.text = '${policy.remainingCount ?? 3}';
  }

  Future<void> _load() async {
    try {
      final load = await widget.api.autoTopup(widget.esimId);
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _unavailable = load.unavailable;
        _applyPolicy(load.policy);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Unable to load auto top-up.';
      });
    }
  }

  TopupOffer? get _selected {
    for (final topup in widget.topups) {
      if (topup.id == _packageId) {
        return topup;
      }
    }
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saved = false;
    });
    final selected = _selected;
    if (selected == null) {
      setState(() => _error = 'Choose a package from Available top-ups.');
      return;
    }
    final canUseData = !selected.isUnlimited;
    final usageMode = canUseData && _remainingData ? _usageKind : 'disabled';
    if (_enabled && !_expiry && usageMode == 'disabled') {
      setState(() => _error = 'Select at least one condition.');
      return;
    }
    final threshold = int.tryParse(_threshold.text.trim());
    if (usageMode == 'threshold' && (threshold == null || threshold < 1)) {
      setState(() => _error = 'Enter a threshold of at least 1 MB.');
      return;
    }
    final count = int.tryParse(_count.text.trim());
    if (_renewMode == 'fixed_count' && (count == null || count < 0)) {
      setState(() => _error = 'Enter a renewal count of 0 or more.');
      return;
    }

    setState(() => _saving = true);
    try {
      final policy = _policy;
      if (!_enabled && policy != null) {
        await widget.api.deleteAutoTopup(widget.esimId, policy.version);
        if (!mounted) {
          return;
        }
        setState(() => _applyPolicy(null));
      } else if (_enabled) {
        final saved = await widget.api.saveAutoTopup(widget.esimId, {
          'package_id': _packageId,
          'enabled': true,
          'expiry_enabled': _expiry,
          'usage_mode': usageMode,
          'threshold_mb': usageMode == 'threshold' ? threshold : null,
          'renew_mode': _renewMode,
          'remaining_count': _renewMode == 'fixed_count' ? count : null,
          'active_until': policy?.activeUntil,
          'version': policy?.version,
        }, policy?.version);
        if (!mounted) {
          return;
        }
        setState(() => _applyPolicy(saved));
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error is DetailApiException
            ? error.message
            : 'Unable to save auto top-up.';
      });
    }
  }

  String? get _statusText {
    final policy = _policy;
    if (policy == null) {
      return null;
    }
    if (policy.status == 'active' && policy.enabled) {
      return 'Auto top-up is on for this eSIM.';
    }
    if (policy.status == 'paused' || policy.status == 'blocked') {
      return policy.reason.isEmpty
          ? 'Auto top-up is ${policy.status}.'
          : 'Auto top-up is ${policy.status} (${policy.reason.replaceAll('_', ' ')}).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final canUseData = selected != null && !selected.isUnlimited;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: _line),
          const SizedBox(height: 14),
          const Text(
            'Renew',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Automatically buy a package from this list when data runs out or '
            'expires. Uses your balance.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
          ),
          if (_loading) ...[
            const SizedBox(height: 10),
            const Text('Loading auto top-up…', style: TextStyle(color: _muted)),
          ] else if (_unavailable != null) ...[
            const SizedBox(height: 10),
            Text(_unavailable!, style: const TextStyle(color: _muted)),
          ] else ...[
            if (_statusText != null) ...[
              const SizedBox(height: 10),
              Text(
                _statusText!,
                style: const TextStyle(
                  color: _successColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              activeThumbColor: _accent,
              onChanged: _saving ? null : (v) => setState(() => _enabled = v),
              title: const Text(
                'Enable auto top-up',
                style: TextStyle(color: _ink, fontSize: 14),
              ),
            ),
            if (_enabled) ...[
              DropdownButtonFormField<String>(
                initialValue: selected?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Package'),
                items: [
                  for (final topup in widget.topups)
                    DropdownMenuItem(
                      value: topup.id,
                      child: Text(topup.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _packageId = value ?? ''),
              ),
              const SizedBox(height: 12),
              const Text(
                'When to auto top-up',
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _expiry,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _expiry = v ?? false),
                title: const Text('Current plan expires'),
              ),
              if (canUseData) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _remainingData,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _remainingData = v ?? false),
                  title: const Text('Remaining data'),
                ),
                if (_remainingData)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: RadioGroup<String>(
                      groupValue: _usageKind,
                      onChanged: (v) {
                        if (!_saving && v != null) {
                          setState(() => _usageKind = v);
                        }
                      },
                      child: Column(
                        children: [
                          const RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: 'threshold',
                            title: Text('Below threshold'),
                          ),
                          if (_usageKind == 'threshold')
                            TextField(
                              controller: _threshold,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Threshold (MB)',
                              ),
                            ),
                          const RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: 'zero',
                            title: Text('Reaches zero'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else
                const Text(
                  'This package is unlimited. Remaining-data triggers '
                  "aren't available.",
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              const SizedBox(height: 12),
              const Text(
                'Renew mode',
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              RadioGroup<String>(
                groupValue: _renewMode,
                onChanged: (v) {
                  if (!_saving && v != null) {
                    setState(() => _renewMode = v);
                  }
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'until_funds',
                      title: Text('Until credits run out'),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'fixed_count',
                      title: Text('Renew a fixed number of times'),
                    ),
                  ],
                ),
              ),
              if (_renewMode == 'fixed_count')
                TextField(
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Remaining renewals',
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: _errorColor)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (_saved)
                  const Text(
                    'Saved',
                    style: TextStyle(
                      color: _successColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Spacer(),
                _SmallButton(
                  label: _saving ? 'Saving…' : 'Save',
                  filled: true,
                  onTap: _saving ? null : _save,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.controller,
    required this.saving,
    required this.saved,
    required this.error,
    required this.dirty,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final bool saved;
  final String? error;
  final bool dirty;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _CardTitle(
          'Notes',
          subtitle:
              'Optional personal note for this eSIM. Only you can see it.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLength: _noteMax,
          minLines: 2,
          maxLines: 4,
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
          decoration: InputDecoration(
            hintText: 'e.g. Japan trip, work phone...',
            hintStyle: const TextStyle(color: _muted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _line),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: const TextStyle(color: _errorColor)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${controller.text.length}/$_noteMax',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            if (saved) ...[
              const SizedBox(width: 10),
              const Text(
                'Saved',
                style: TextStyle(
                  color: _successColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            _SmallButton(
              label: saving ? 'Saving…' : 'Save',
              filled: true,
              onTap: dirty && !saving ? onSave : null,
            ),
          ],
        ),
      ],
    );
  }
}
