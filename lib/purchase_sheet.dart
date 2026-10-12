import 'package:flutter/material.dart';

import 'catalog.dart';
import 'orders_api.dart';
import 'session.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _line = Color(0xFFE4E8F0);
const _errorColor = Color(0xFFD14343);

/// Confirm before the API debits credits. Returns true after a successful order.
Future<bool> showPurchaseSheet(
  BuildContext context, {
  required CatalogPackage package,
  required BillingDisplay display,
  required OrderSender sendOrder,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _PurchaseSheet(
      package: package,
      display: display,
      sendOrder: sendOrder,
      idempotencyKey: newOrderIdempotencyKey(),
    ),
  );
  return result ?? false;
}

class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({
    required this.package,
    required this.display,
    required this.sendOrder,
    required this.idempotencyKey,
  });

  final CatalogPackage package;
  final BillingDisplay display;
  final OrderSender sendOrder;
  final String idempotencyKey;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  bool _busy = false;
  bool _insufficient = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppSession.instance.loadBalance();
  }

  Future<void> _confirm() async {
    if (_busy || _insufficient) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.sendOrder(
      widget.package.id,
      widget.idempotencyKey,
    );
    if (!mounted) {
      return;
    }
    switch (outcome.status) {
      case OrderStatus.success:
        Navigator.of(context).pop(true);
      case OrderStatus.insufficient:
        final missing = formatCatalogPrice(outcome.missing, widget.display);
        setState(() {
          _busy = false;
          _insufficient = true;
          _error = missing.isEmpty
              ? 'Not enough balance.'
              : 'Not enough balance. You need $missing more.';
        });
      case OrderStatus.failed:
        setState(() {
          _busy = false;
          _error = outcome.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    final data = packageDataLabel(package);
    final validity = validityHeading(package.validityDays);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final navBar = MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
    final bottomInset = keyboard > navBar ? keyboard : navBar;

    return PopScope(
      canPop: !_busy,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Text(
                  'Confirm purchase',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: ListenableBuilder(
                  listenable: AppSession.instance,
                  builder: (context, _) {
                    final balance = formatCatalogPrice(
                      AppSession.instance.balance,
                      widget.display,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$data - $validity',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Row(label: 'Data', value: data),
                        _Row(label: 'Validity', value: validity),
                        _Row(
                          label: 'Price',
                          value: formatCatalogPrice(
                            package.priceUsd,
                            widget.display,
                          ),
                          listValue: struckListPrice(
                            package.listPriceUsd,
                            package.priceUsd,
                            widget.display,
                          ),
                          strong: true,
                        ),
                        if (balance.isNotEmpty) ...[
                          const Divider(height: 16, color: _line),
                          _Row(label: 'Your balance', value: balance),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'Balance is shown for reference. Available funds '
                          'are checked again when you confirm.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: _errorColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _SheetButton(
                        label: 'Cancel',
                        filled: false,
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SheetButton(
                        label: _busy ? 'Purchasing…' : 'Confirm purchase',
                        filled: true,
                        busy: _busy,
                        onTap: _busy || _insufficient ? null : _confirm,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.listValue,
    this.strong = false,
  });

  final String label;
  final String value;
  final String? listValue;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (listValue != null)
                Text(
                  listValue!,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: _muted,
                  ),
                ),
              Text(
                value,
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final background = filled
        ? (enabled || busy ? _accent : _accent.withValues(alpha: 0.45))
        : Colors.white;
    final foreground = filled ? Colors.white : (enabled ? _ink : _muted);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: filled ? null : Border.all(color: _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
