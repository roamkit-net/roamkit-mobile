import 'package:flutter/material.dart';

import 'auth_sheet.dart';
import 'esim.dart';
import 'esim_api.dart';
import 'esim_detail_screen.dart';
import 'session.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _remainingFill = Color(0xFFDCEBFF);

class EsimsScreen extends StatefulWidget {
  const EsimsScreen({super.key, this.loader});

  final Future<List<OwnedEsim>> Function()? loader;

  @override
  State<EsimsScreen> createState() => _EsimsScreenState();
}

class _EsimsScreenState extends State<EsimsScreen> {
  List<OwnedEsim> _esims = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_onSession);
    if (AppSession.instance.isSignedIn) {
      _load();
    }
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) {
      return;
    }
    if (AppSession.instance.isSignedIn) {
      _load();
    } else {
      setState(() {
        _esims = const [];
        _error = null;
        _loading = false;
      });
    }
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
        _loading = false;
      });
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
        final sections = partitionEsims(_esims);
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
                            onOpen: _open,
                          ),
                        if (sections.expired.isNotEmpty)
                          _Section(
                            title: 'Expired (${sections.expired.length})',
                            esims: sections.expired,
                            onOpen: _open,
                          ),
                        if (sections.archived.isNotEmpty)
                          _Section(
                            title: 'Archived (${sections.archived.length})',
                            esims: sections.archived,
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
    required this.onOpen,
  });

  final String title;
  final List<OwnedEsim> esims;
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
          _EsimCard(esim: esim, onTap: () => onOpen(esim)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EsimCard extends StatelessWidget {
  const _EsimCard({required this.esim, required this.onTap});

  final OwnedEsim esim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final validity = esim.validityLabel;
    final flag = esim.flagUrl;
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
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: esim.destination),
                                if (validity != null)
                                  TextSpan(
                                    text: '  $validity',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
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
