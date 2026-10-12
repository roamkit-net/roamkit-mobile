import 'package:flutter/material.dart';

import 'auth_sheet.dart';
import 'catalog.dart';
import 'esim.dart';
import 'esim_api.dart';
import 'esim_detail_api.dart';
import 'esim_detail_screen.dart';
import 'session.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _remainingFill = Color(0xFFDCEBFF);

List<OwnedEsim> filterEsims(List<OwnedEsim> esims, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return esims;
  }
  return [
    for (final esim in esims)
      if (esim.iccid.toLowerCase().contains(needle) ||
          esim.note.toLowerCase().contains(needle))
        esim,
  ];
}

class EsimsScreen extends StatefulWidget {
  const EsimsScreen({
    super.key,
    this.loader,
    this.regionImage,
    this.packageLoader,
  });

  final Future<List<OwnedEsim>> Function()? loader;
  final Future<String?> Function(String slug)? regionImage;
  final Future<List<AppliedPackage>> Function(int esimId)? packageLoader;

  @override
  State<EsimsScreen> createState() => _EsimsScreenState();
}

class _EsimsScreenState extends State<EsimsScreen> {
  List<OwnedEsim> _esims = const [];
  Map<String, String> _regionImages = const {};
  Map<int, PackageExpiryBadge> _expiryBadges = const {};
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_onSession);
    if (AppSession.instance.isSignedIn) {
      _load();
      _loadRegionImages();
    }
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSession);
    _search.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) {
      return;
    }
    if (AppSession.instance.isSignedIn) {
      _load();
      _loadRegionImages();
    } else {
      setState(() {
        _esims = const [];
        _regionImages = const {};
        _expiryBadges = const {};
        _query = '';
        _search.clear();
        _error = null;
        _loading = false;
      });
    }
  }

  Future<void> _loadRegionImages() async {
    final loader = widget.regionImage ?? fetchLocationImage;
    final images = <String, String>{};
    for (final slug in const ['europe', 'global']) {
      try {
        final image = await loader(slug);
        if (image != null && image.isNotEmpty) {
          images[slug] = image;
        }
      } catch (_) {
        // A missing region image leaves the card frame empty.
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _regionImages = images);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? fetchMyEsims;
      final esims = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _esims = esims;
        _expiryBadges = const {};
        _loading = false;
      });
      await _loadExpiryBadges(esims);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load eSIMs.';
      });
    }
  }

  Future<void> _loadExpiryBadges(List<OwnedEsim> esims) async {
    final loader = widget.packageLoader ?? fetchEsimPackages;
    final entries = await Future.wait(
      esims.map((esim) async {
        try {
          final badge = latestPackageExpiryBadge(await loader(esim.id));
          return badge == null ? null : MapEntry(esim.id, badge);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted || !AppSession.instance.isSignedIn) {
      return;
    }
    setState(() {
      _expiryBadges = Map.fromEntries(
        entries.whereType<MapEntry<int, PackageExpiryBadge>>(),
      );
    });
  }

  Future<void> _open(OwnedEsim esim) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EsimDetailScreen(esim: esim),
      ),
    );
    if (mounted && AppSession.instance.isSignedIn) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSession.instance,
      builder: (context, _) {
        final signedIn = AppSession.instance.isSignedIn;
        final filtered = filterEsims(_esims, _query);
        final sections = partitionEsims(filtered);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'My eSIMs',
              style: TextStyle(
                color: _ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            if (signedIn) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search ICCID or Note',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: !signedIn
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: _Pill(
                        label: 'Log in',
                        onTap: () => showAuthSheet(context, signUp: false),
                      ),
                    )
                  : _loading && _esims.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent),
                    )
                  : _error != null && _esims.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: const TextStyle(color: _ink)),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty && _esims.isNotEmpty
                  ? const Text(
                      'No matching eSIMs.',
                      style: TextStyle(color: _muted, fontSize: 15),
                    )
                  : sections.isEmpty
                  ? const Text(
                      'No eSIMs yet.',
                      style: TextStyle(color: _muted, fontSize: 15),
                    )
                  : ListView(
                      children: [
                        if (sections.active.isNotEmpty)
                          _Section(
                            title: 'Active (${sections.active.length})',
                            esims: sections.active,
                            regionImages: _regionImages,
                            expiryBadges: _expiryBadges,
                            onOpen: _open,
                          ),
                        if (sections.expired.isNotEmpty)
                          _Section(
                            title: 'Expired (${sections.expired.length})',
                            esims: sections.expired,
                            regionImages: _regionImages,
                            expiryBadges: _expiryBadges,
                            onOpen: _open,
                          ),
                        if (sections.archived.isNotEmpty)
                          _Section(
                            title: 'Archived (${sections.archived.length})',
                            esims: sections.archived,
                            regionImages: _regionImages,
                            expiryBadges: _expiryBadges,
                            onOpen: _open,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.esims,
    required this.regionImages,
    required this.expiryBadges,
    required this.onOpen,
  });

  final String title;
  final List<OwnedEsim> esims;
  final Map<String, String> regionImages;
  final Map<int, PackageExpiryBadge> expiryBadges;
  final ValueChanged<OwnedEsim> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _muted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        for (final esim in esims) ...[
          _EsimCard(
            esim: esim,
            regionImages: regionImages,
            expiryBadge: expiryBadges[esim.id],
            onTap: () => onOpen(esim),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EsimCard extends StatelessWidget {
  const _EsimCard({
    required this.esim,
    required this.regionImages,
    required this.expiryBadge,
    required this.onTap,
  });

  final OwnedEsim esim;
  final Map<String, String> regionImages;
  final PackageExpiryBadge? expiryBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final validity = esim.validityLabel;
    final slug = regionIconSlug(esim.destination);
    final flag = esim.flagUrl ?? (slug == null ? null : regionImages[slug]);
    final remaining = esimStage(esim.status) == EsimStage.inUse
        ? remainingDataFraction(
            remainingMb: esim.usageRemainingMb,
            totalMb: esim.usageTotalMb,
            isUnlimited: esim.usageIsUnlimited,
          )
        : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        key: ValueKey('esim-card-${esim.id}'),
        decoration: BoxDecoration(
          gradient: remaining == null
              ? null
              : LinearGradient(
                  colors: const [
                    _remainingFill,
                    _remainingFill,
                    Colors.white,
                    Colors.white,
                  ],
                  stops: [0, remaining, remaining, 1],
                ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: flag == null
                          ? const SizedBox(width: 36, height: 26)
                          : Image.network(
                              flag,
                              width: 36,
                              height: 26,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 36, height: 26),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  esim.destination,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (expiryBadge != null) ...[
                                const SizedBox(width: 8),
                                _CardExpiryBadge(badge: expiryBadge!),
                              ] else if (validity != null)
                                Text(
                                  '  $validity',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            esimUsageLine(esim),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatEsimStatus(esim.status),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ICCID: ${esim.iccid}',
                  style: const TextStyle(color: _ink, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Note: ${esim.note}',
                  style: const TextStyle(color: _ink, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardExpiryBadge extends StatelessWidget {
  const _CardExpiryBadge({required this.badge});

  final PackageExpiryBadge badge;

  @override
  Widget build(BuildContext context) {
    final color = badge.urgent
        ? const Color(0xFFD14343)
        : const Color(0xFF1E8E5A);
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE4E8F0)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
