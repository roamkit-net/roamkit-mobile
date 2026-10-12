import 'package:flutter/material.dart';

import 'auth_sheet.dart';
import 'catalog.dart';
import 'orders_api.dart';
import 'purchase_sheet.dart';
import 'session.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _accentEnd = Color(0xFF9B6DFF);

class LocationScreen extends StatefulWidget {
  const LocationScreen({
    super.key,
    required this.slug,
    required this.title,
    required this.display,
    this.imageUrl,
    this.loader,
    this.preview,
    this.orderSender,
  });

  final String slug;
  final String title;
  final String? imageUrl;
  final BillingDisplay display;
  final Future<LocationDetailData> Function(String slug)? loader;
  final LocationDetailData? preview;
  final OrderSender? orderSender;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  LocationDetailData? _detail;
  String? _error;
  bool _loading = false;
  String _service = 'data';
  String _amount = 'fixed';
  String? _selectedId;
  String? _authToken;

  @override
  void initState() {
    super.initState();
    _authToken = AppSession.instance.accessToken;
    AppSession.instance.addListener(_onAuth);
    final preview = widget.preview;
    if (preview != null) {
      _detail = preview;
      _service = _defaultService(preview);
      _amount = _defaultAmount(preview);
      return;
    }
    _loading = true;
    _load();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final token = AppSession.instance.accessToken;
    if (token == _authToken || widget.preview != null) {
      _authToken = token;
      return;
    }
    _authToken = token;
    _load(keepSelection: true);
  }

  String _defaultService(LocationDetailData detail) {
    final hasData = detail.packages.any(
      (package) => !packageIsDataCallsTexts(package),
    );
    return hasData ? 'data' : 'data_calls_texts';
  }

  String _defaultAmount(LocationDetailData detail) {
    final dataPackages = packagesForService(detail.packages, 'data');
    return resolveAmountFilter('fixed', dataPackages);
  }

  Future<void> _load({bool keepSelection = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? fetchLocationDetail;
      final detail = await loader(widget.slug);
      if (!mounted) {
        return;
      }
      setState(() {
        final keep =
            keepSelection &&
            detail.packages.any((package) => package.id == _selectedId);
        _detail = detail;
        if (!keep) {
          _service = _defaultService(detail);
          _amount = _defaultAmount(detail);
          _selectedId = null;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load plans.';
      });
    }
  }

  void _selectService(String service) {
    setState(() {
      _service = service;
      _selectedId = null;
      final detail = _detail;
      if (detail != null && service == 'data') {
        _amount = resolveAmountFilter(
          _amount,
          packagesForService(detail.packages, 'data'),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final visible = detail == null
        ? const <CatalogPackage>[]
        : _visiblePackages(detail);
    CatalogPackage? selected;
    for (final package in visible) {
      if (package.id == _selectedId) {
        selected = package;
        break;
      }
    }

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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TitleBar(title: widget.title),
                  const SizedBox(height: 8),
                  Expanded(child: _body(detail, visible)),
                  const SizedBox(height: 10),
                  _BuyNowButton(
                    enabled: selected != null,
                    onPressed: selected == null ? null : () => _buy(selected!),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(CatalogPackage package) async {
    if (!AppSession.instance.isSignedIn) {
      await showAuthSheet(context, signUp: false);
      return;
    }
    final purchased = await showPurchaseSheet(
      context,
      package: package,
      display: widget.display,
      sendOrder: widget.orderSender ?? createOrder,
    );
    if (!purchased || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Purchase complete.')));
    await AppSession.instance.loadBalance();
  }

  Widget _body(LocationDetailData? detail, List<CatalogPackage> visible) {
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null && detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _ink)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final hasData = detail.packages.any(
      (package) => !packageIsDataCallsTexts(package),
    );
    final hasCalls = detail.packages.any(packageIsDataCallsTexts);
    final servicePackages = packagesForService(detail.packages, _service);
    final showAmount = shouldShowAmountFilter(servicePackages, _service);
    final groups = groupPackagesByValidity(visible);

    return ListView(
      children: [
        _SummaryCard(
          title: widget.title,
          imageUrl: widget.imageUrl,
          coverageType: detail.coverageType,
          coverages: detail.coverages,
        ),
        const SizedBox(height: 18),
        _ServiceTabs(
          service: _service,
          showData: hasData,
          showCalls: hasCalls,
          onSelected: _selectService,
        ),
        if (showAmount) ...[
          const SizedBox(height: 16),
          _AmountPills(
            amount: _amount,
            onSelected: (amount) => setState(() {
              _amount = amount;
              _selectedId = null;
            }),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Choose your package',
          style: TextStyle(
            color: _ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        if (groups.isEmpty)
          const Text(
            'No plans in this filter.',
            style: TextStyle(color: _muted),
          )
        else
          for (final group in groups) ...[
            Text(
              validityHeading(group.days),
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final package in group.packages) ...[
              _PackageCard(
                label: packageDataLabel(package),
                price: formatCatalogPrice(package.priceUsd, widget.display),
                listPrice: _listPrice(package),
                selected: package.id == _selectedId,
                onTap: () => setState(() => _selectedId = package.id),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  String? _listPrice(CatalogPackage package) {
    final list = formatCatalogPrice(package.listPriceUsd, widget.display);
    final charge = formatCatalogPrice(package.priceUsd, widget.display);
    if (list.isEmpty || list == charge) {
      return null;
    }
    return list;
  }

  List<CatalogPackage> _visiblePackages(LocationDetailData detail) {
    final servicePackages = packagesForService(detail.packages, _service);
    final amount = resolveAmountFilter(_amount, servicePackages);
    if (!shouldShowAmountFilter(servicePackages, _service)) {
      return servicePackages;
    }
    return filterPackagesByAmount(servicePackages, amount, _service);
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left, color: _ink, size: 28),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.imageUrl,
    required this.coverageType,
    required this.coverages,
  });

  final String title;
  final String? imageUrl;
  final String coverageType;
  final List<LocationCoverage> coverages;

  @override
  Widget build(BuildContext context) {
    final networks = flattenNetworks(coverages);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl == null
                    ? const SizedBox(width: 36, height: 26)
                    : Image.network(
                        imageUrl!,
                        width: 36,
                        height: 26,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(width: 36, height: 26),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE6EAF2)),
          ),
          if (coverageType == 'local' && networks.isNotEmpty)
            _LocalNetworks(networks: networks)
          else if (coverages.isNotEmpty)
            _CoverageCount(coverages: coverages),
          const SizedBox(height: 12),
          const _CompatibilityRow(),
        ],
      ),
    );
  }
}

class _LocalNetworks extends StatelessWidget {
  const _LocalNetworks({required this.networks});

  final List<CoverageNetwork> networks;

  @override
  Widget build(BuildContext context) {
    final primary = networks.first;
    final others = networks.length - 1;
    final badge = highestNetworkType(primary.types);
    return Row(
      children: [
        const Icon(Icons.signal_cellular_alt, color: _ink, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            primary.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: _ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (others > 0) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showNetworks(context, networks),
            child: Text(
              others == 1 ? '1 other' : '$others others',
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CoverageCount extends StatelessWidget {
  const _CoverageCount({required this.coverages});

  final List<LocationCoverage> coverages;

  @override
  Widget build(BuildContext context) {
    final count = coverages.length;
    final label = count == 1
        ? '1 Country and Network'
        : '$count Countries and Networks';
    return GestureDetector(
      onTap: () => _showCoverages(context, coverages),
      child: Row(
        children: [
          const Icon(Icons.public, color: _ink, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompatibilityRow extends StatelessWidget {
  const _CompatibilityRow();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showCompatibility(context),
      behavior: HitTestBehavior.opaque,
      child: const Row(
        children: [
          Icon(Icons.smartphone_outlined, color: _ink, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Is this device compatible?',
              style: TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _YesChip(),
        ],
      ),
    );
  }
}

class _YesChip extends StatelessWidget {
  const _YesChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, color: _accent, size: 16),
          SizedBox(width: 2),
          Text(
            'Yes',
            style: TextStyle(
              color: _accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTabs extends StatelessWidget {
  const _ServiceTabs({
    required this.service,
    required this.showData,
    required this.showCalls,
    required this.onSelected,
  });

  final String service;
  final bool showData;
  final bool showCalls;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showData)
          _ServiceTab(
            label: 'Data',
            selected: !showCalls || service == 'data',
            onTap: showCalls ? () => onSelected('data') : null,
          ),
        if (showData && showCalls) const SizedBox(width: 22),
        if (showCalls)
          _ServiceTab(
            label: 'Data / Calls / Texts',
            selected: !showData || service == 'data_calls_texts',
            onTap: showData ? () => onSelected('data_calls_texts') : null,
          ),
      ],
    );
  }
}

class _ServiceTab extends StatelessWidget {
  const _ServiceTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? _ink : _muted,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 3,
            width: selected ? 36 : 0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(colors: [_accent, _accentEnd]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountPills extends StatelessWidget {
  const _AmountPills({required this.amount, required this.onSelected});

  final String amount;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AmountPill(
            label: 'Fixed data',
            selected: amount == 'fixed',
            onTap: () => onSelected('fixed'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AmountPill(
            label: 'Unlimited',
            selected: amount == 'unlimited',
            onTap: () => onSelected('unlimited'),
          ),
        ),
      ],
    );
  }
}

class _AmountPill extends StatelessWidget {
  const _AmountPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _ink : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : _ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
    this.listPrice,
  });

  final String label;
  final String price;
  final String? listPrice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (listPrice != null)
                    Text(
                      listPrice!,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: _muted,
                      ),
                    ),
                  Text(
                    price,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyNowButton extends StatelessWidget {
  const _BuyNowButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _accent : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: enabled ? null : Border.all(color: const Color(0xFFE4E8F0)),
          ),
          child: Text(
            'Buy now',
            style: TextStyle(
              color: enabled ? Colors.white : _muted,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

void _showNetworks(BuildContext context, List<CoverageNetwork> networks) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          children: [
            const Text(
              'Networks',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final network in networks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  [
                    network.name,
                    if (highestNetworkType(network.types) != null)
                      highestNetworkType(network.types)!,
                  ].join(' · '),
                  style: const TextStyle(color: _ink, fontSize: 15),
                ),
              ),
          ],
        ),
      );
    },
  );
}

void _showCoverages(BuildContext context, List<LocationCoverage> coverages) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          children: [
            const Text(
              'Countries and Networks',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final coverage in coverages) ...[
              const SizedBox(height: 12),
              Text(
                coverage.name.isEmpty ? coverage.code : coverage.name,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final network in coverage.networks)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    network.name,
                    style: const TextStyle(color: _muted, fontSize: 14),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

void _showCompatibility(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Check compatibility',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'A RoamKit eSIM needs a device that supports eSIMs, is not carrier-locked, and is not rooted.',
                style: TextStyle(color: _ink, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      );
    },
  );
}
