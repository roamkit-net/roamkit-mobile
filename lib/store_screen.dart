import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_sheet.dart';
import 'catalog.dart';
import 'esims_screen.dart';
import 'location_screen.dart';
import 'profile_screen.dart';
import 'session.dart';
import 'viewer_country.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _accentEnd = Color(0xFF9B6DFF);

const _tabs = ['popular', 'local', 'regional', 'global'];

const _tabLabels = {
  'popular': 'Popular',
  'local': 'Local',
  'regional': 'Regional',
  'global': 'Global',
};

const _tabCopy = {
  'popular':
      'Explore our most popular eSIMs — packages start from the shown price.',
  'local': 'Country-specific plans with local coverage where you land.',
  'regional': 'One plan across multiple countries in the same region.',
  'global': 'Worldwide coverage for multi-stop trips.',
};

class StoreScreen extends StatefulWidget {
  const StoreScreen({
    super.key,
    this.initialLocations,
    this.initialDisplay = BillingDisplay.fallback,
    this.loadCatalog = false,
    this.detailLoader,
  });

  final List<CatalogLocation>? initialLocations;
  final BillingDisplay initialDisplay;
  final bool loadCatalog;
  final Future<LocationDetailData> Function(String slug)? detailLoader;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<CatalogLocation> _locations = const [];
  BillingDisplay _display = BillingDisplay.fallback;
  String _tab = 'popular';
  String _section = 'store';
  String _debouncedQuery = '';
  String? _viewerCountry;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locations = widget.initialLocations ?? const [];
    _display = widget.initialDisplay;
    if (widget.loadCatalog) {
      _loading = _locations.isEmpty;
      _load();
      AppSession.instance.restore();
      _resolveCountry();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        fetchAllLocations(),
        fetchBillingDisplay(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _locations = results[0] as List<CatalogLocation>;
        _display = results[1] as BillingDisplay;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load destinations.';
      });
    }
  }

  Future<void> _resolveCountry() async {
    final country = await resolveViewerCountry();
    if (!mounted) {
      return;
    }
    setState(() => _viewerCountry = country);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) {
        return;
      }
      setState(() => _debouncedQuery = value);
    });
    setState(() {});
  }

  bool get _searching => _debouncedQuery.trim().isNotEmpty;

  void _openLocation(CatalogLocation location) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocationScreen(
          slug: location.slug,
          title: location.title,
          imageUrl: location.imageSrc,
          display: _display,
          loader: widget.detailLoader,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _searching
        ? matchLocations(_locations, _debouncedQuery)
        : null;
    final rows = results == null
        ? locationsForTab(_locations, _tab, viewerCountry: _viewerCountry)
        : [...results.primary, ...results.broader];

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_section == 'profile')
                    const Expanded(child: ProfileScreen())
                  else if (_section == 'esims')
                    const Expanded(child: EsimsScreen())
                  else ...[
                    _Header(display: _display),
                    const SizedBox(height: 14),
                    _SearchField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      onClear: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        setState(() => _debouncedQuery = '');
                      },
                    ),
                    if (!_searching) ...[
                      const SizedBox(height: 16),
                      _TabBar(
                        selected: _tab,
                        onSelected: (tab) => setState(() => _tab = tab),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _tabCopy[_tab] ?? '',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: _DestinationList(
                        loading: _loading,
                        error: _error,
                        rows: rows,
                        broaderCount: results?.broader.length ?? 0,
                        primaryCount: results?.primary.length ?? rows.length,
                        searching: _searching,
                        display: _display,
                        onRetry: _load,
                        onOpen: _openLocation,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _BottomNav(
                    section: _section,
                    onSelect: (section) => setState(() => _section = section),
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

class _Header extends StatelessWidget {
  const _Header({required this.display});

  final BillingDisplay display;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;
        final signedIn = session.isSignedIn;
        final label = signedIn
            ? formatCatalogPrice(session.balance, display)
            : 'Log in';
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Store',
                style: TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
            GestureDetector(
              onTap: signedIn
                  ? () => AppSession.instance.loadBalance()
                  : () => showAuthSheet(context, signUp: false),
              child: signedIn
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: _ink, fontSize: 15),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: 'Where do you need an eSIM?',
        hintStyle: const TextStyle(color: _muted, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search, color: _accent),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, color: _muted),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tab in _tabs)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelected(tab),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _tabLabels[tab] ?? tab,
                    style: TextStyle(
                      color: tab == selected ? _accent : _muted,
                      fontSize: 15,
                      fontWeight: tab == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: tab == selected ? 28 : 0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        colors: [_accent, _accentEnd],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DestinationList extends StatelessWidget {
  const _DestinationList({
    required this.loading,
    required this.error,
    required this.rows,
    required this.primaryCount,
    required this.broaderCount,
    required this.searching,
    required this.display,
    required this.onRetry,
    required this.onOpen,
  });

  final bool loading;
  final String? error;
  final List<CatalogLocation> rows;
  final int primaryCount;
  final int broaderCount;
  final bool searching;
  final BillingDisplay display;
  final VoidCallback onRetry;
  final ValueChanged<CatalogLocation> onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (error != null && rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, style: const TextStyle(color: _ink)),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return const Center(
        child: Text('No destinations match.', style: TextStyle(color: _muted)),
      );
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final showBroaderLabel =
            searching && broaderCount > 0 && index == primaryCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showBroaderLabel)
              const Padding(
                padding: EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  'Also in regional and global plans',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            _DestinationRow(
              location: rows[index],
              display: display,
              onOpen: () => onOpen(rows[index]),
            ),
          ],
        );
      },
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.location,
    required this.display,
    required this.onOpen,
  });

  final CatalogLocation location;
  final BillingDisplay display;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final price = formatCatalogPrice(location.minPriceUsd, display);
    final image = location.imageSrc;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 21),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: image == null
                    ? const SizedBox(width: 32, height: 22)
                    : Image.network(
                        image,
                        width: 32,
                        height: 22,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(width: 32, height: 22),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  location.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (price.isNotEmpty)
                Text(
                  price,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.section, required this.onSelect});

  final String section;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavItem(
              icon: Icons.shopping_bag_outlined,
              label: 'Store',
              active: section == 'store',
              onTap: () => onSelect('store'),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.sim_card_outlined,
              label: 'My eSIMs',
              active: section == 'esims',
              onTap: () => onSelect('esims'),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              active: section == 'profile',
              onTap: () => onSelect('profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? _accent : _muted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            width: active ? 28 : 0,
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
