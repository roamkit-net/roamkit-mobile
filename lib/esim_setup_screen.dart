import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'esim.dart';
import 'euicc.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _errorColor = Color(0xFFD14343);

const _manualSteps = [
  _ManualStep('Connections', 'assets/images/esim_manual/connections.png'),
  _ManualStep('SIM manager', 'assets/images/esim_manual/sim_manager.png'),
  _ManualStep('Add eSIM', 'assets/images/esim_manual/add_esim.png'),
  _ManualStep('Scan QR code', 'assets/images/esim_manual/scan_qr.png'),
  _ManualStep(
    'Enter activation code',
    'assets/images/esim_manual/enter_code.png',
  ),
  _ManualStep('Done', 'assets/images/esim_manual/done.jpg'),
];

enum EsimSetupView { choices, manual, qr }

typedef ActivationCopier = Future<void> Function(String code);

class EsimSetupScreen extends StatefulWidget {
  const EsimSetupScreen({
    super.key,
    required this.esim,
    this.installer,
    this.copier,
    this.view = EsimSetupView.choices,
  });

  final OwnedEsim esim;
  final EsimInstaller? installer;
  final ActivationCopier? copier;

  /// First view shown. Back from this view leaves the screen.
  final EsimSetupView view;

  @override
  State<EsimSetupScreen> createState() => _EsimSetupScreenState();
}

class _EsimSetupScreenState extends State<EsimSetupScreen> {
  late EsimSetupView _pane = widget.view;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final code = _activationCode;
    if (widget.view == EsimSetupView.manual && code != null) {
      _copy(code);
    }
  }

  String? get _activationCode {
    return resolveLpaUri(
      lpa: widget.esim.lpa,
      activationCode: widget.esim.matchingId,
    );
  }

  Future<void> _install() async {
    final link = androidSetupLink(
      lpa: widget.esim.lpa,
      matchingId: widget.esim.matchingId,
    );
    if (link == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final installer = widget.installer ?? installEsim;
      final message = await installer(link);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'Could not install the eSIM.';
      });
    }
  }

  Future<void> _openManual() async {
    setState(() => _pane = EsimSetupView.manual);
    final code = _activationCode;
    if (code != null) {
      await _copy(code);
    }
  }

  Future<void> _copy(String code) async {
    try {
      final copier = widget.copier ?? _copyToClipboard;
      await copier(code);
      if (!mounted) {
        return;
      }
      setState(() => _copied = true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _copied = false);
    }
  }

  void _back() {
    if (_pane != widget.view) {
      setState(() => _pane = EsimSetupView.choices);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final esim = widget.esim;
    final canInstall = _activationCode != null;

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
                  Row(
                    children: [
                      IconButton(
                        onPressed: _back,
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
                      const Expanded(
                        child: Text(
                          'Set up your eSIM',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_pane == EsimSetupView.qr)
                    Expanded(
                      child: _QrView(
                        title: esim.destination,
                        iccid: esim.iccid,
                        url: esim.qrcodeUrl,
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          Text(
                            'ICCID: ${esim.iccid}',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            esim.destination,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_pane == EsimSetupView.choices)
                            EsimInstallActions(
                              busy: _busy,
                              canInstall: canInstall,
                              error: _error,
                              onInstall: _install,
                              onManual: _openManual,
                              onQr: () =>
                                  setState(() => _pane = EsimSetupView.qr),
                            )
                          else
                            _ManualGuide(
                              code: _activationCode,
                              copied: _copied,
                              onCopy: _activationCode == null
                                  ? null
                                  : () => _copy(_activationCode!),
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

Future<void> _copyToClipboard(String code) {
  return Clipboard.setData(ClipboardData(text: code));
}

class _ManualStep {
  const _ManualStep(this.label, this.asset);

  final String label;
  final String asset;
}

class EsimInstallActions extends StatelessWidget {
  const EsimInstallActions({
    super.key,
    required this.busy,
    required this.canInstall,
    required this.error,
    required this.onInstall,
    required this.onManual,
    required this.onQr,
  });

  final bool busy;
  final bool canInstall;
  final String? error;
  final VoidCallback onInstall;
  final VoidCallback onManual;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          label: busy ? 'Opening…' : 'Install eSIM',
          filled: canInstall || busy,
          enabled: canInstall && !busy,
          onTap: onInstall,
        ),
        if (!canInstall) ...[
          const SizedBox(height: 10),
          const Text(
            'This eSIM has no activation code yet.',
            style: TextStyle(color: _errorColor, fontSize: 14),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: const TextStyle(
              color: _errorColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _ActionButton(
          label: 'Manual install',
          filled: false,
          enabled: true,
          onTap: onManual,
        ),
        const SizedBox(height: 10),
        _ActionButton(
          label: 'QR code',
          filled: false,
          enabled: true,
          onTap: onQr,
        ),
        const SizedBox(height: 14),
        const Text(
          'Data Roaming must be turned on for the service to work.',
          style: TextStyle(color: _errorColor, fontSize: 14, height: 1.35),
        ),
      ],
    );
  }
}

class _ManualGuide extends StatelessWidget {
  const _ManualGuide({
    required this.code,
    required this.copied,
    required this.onCopy,
  });

  final String? code;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (code != null)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Activation code',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      code!,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      copied ? 'Copied' : 'Tap to copy',
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (var index = 0; index < _manualSteps.length; index++) ...[
          const SizedBox(height: 16),
          Text(
            '${index + 1}. ${_manualSteps[index].label}',
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(_manualSteps[index].asset, fit: BoxFit.fitWidth),
          ),
        ],
      ],
    );
  }
}

class _QrView extends StatelessWidget {
  const _QrView({required this.title, required this.iccid, required this.url});

  final String title;
  final String iccid;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: url.isEmpty
              ? const Text(
                  'This eSIM has no QR code yet.',
                  style: TextStyle(color: _errorColor, fontSize: 14),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ICCID: $iccid',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _accent : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: filled ? null : Border.all(color: const Color(0xFFE4E8F0)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : (enabled ? _ink : _muted),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
