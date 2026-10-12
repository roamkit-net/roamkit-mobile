class OwnedEsim {
  const OwnedEsim({
    required this.id,
    required this.status,
    required this.locationTitle,
    required this.packageTitle,
    required this.countryCode,
    required this.dataAllowance,
    required this.validityDays,
    required this.usageRemainingMb,
    required this.usageTotalMb,
    required this.usageIsUnlimited,
    required this.usageExpiredAt,
    required this.issuedAt,
    required this.createdAt,
    required this.archivedAt,
    required this.lpa,
    required this.matchingId,
    required this.qrcodeUrl,
    this.iccid = '',
    this.note = '',
  });

  final int id;
  final String status;
  final String locationTitle;
  final String packageTitle;
  final String countryCode;
  final String dataAllowance;
  final int? validityDays;
  final int? usageRemainingMb;
  final int? usageTotalMb;
  final bool usageIsUnlimited;
  final String? usageExpiredAt;
  final String? issuedAt;
  final String? createdAt;
  final String? archivedAt;
  final String lpa;
  final String matchingId;
  final String qrcodeUrl;
  final String iccid;
  final String note;

  factory OwnedEsim.fromJson(Map<String, dynamic> json) {
    return OwnedEsim(
      id: json['id'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      locationTitle: json['location_title'] as String? ?? '',
      packageTitle: json['package_title'] as String? ?? '',
      countryCode: json['country_code'] as String? ?? '',
      dataAllowance: json['data_allowance'] as String? ?? '',
      validityDays: json['validity_days'] as int?,
      usageRemainingMb: _asInt(json['usage_remaining_mb']),
      usageTotalMb: _asInt(json['usage_total_mb']),
      usageIsUnlimited: json['usage_is_unlimited'] as bool? ?? false,
      usageExpiredAt: _asString(json['usage_expired_at']),
      issuedAt: _asString(json['issued_at']),
      createdAt: _asString(json['created_at']),
      archivedAt: _asString(json['archived_at']),
      lpa: json['lpa'] as String? ?? '',
      matchingId: json['matching_id'] as String? ?? '',
      qrcodeUrl: json['qrcode_url'] as String? ?? '',
      iccid: json['iccid'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  String get destination {
    final location = locationTitle.trim();
    if (location.isNotEmpty) {
      return location;
    }
    final title = packageTitle.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return 'eSIM';
  }

  String? get validityLabel {
    final days = validityDays;
    if (days == null) {
      return null;
    }
    return days == 1 ? '1 day' : '$days days';
  }

  String? get flagUrl {
    final code = countryCode.trim().toLowerCase();
    if (code.isEmpty) {
      return null;
    }
    return 'https://flagcdn.com/w80/$code.png';
  }
}

/// Catalog slug for a regional card that has no country flag.
String? regionIconSlug(String destination) {
  final key = destination.trim().toLowerCase();
  if (key == 'europe') {
    return 'europe';
  }
  const global = {
    'global',
    'discover global',
    'world',
    'discover',
    'discover-global',
  };
  if (global.contains(key)) {
    return 'global';
  }
  return null;
}

enum EsimStage { purchased, inUse, expired }

/// Which detail layout an eSIM gets. Anything not yet in use still installs.
EsimStage esimStage(String status) {
  switch (status) {
    case 'in_use':
    case 'active':
    case 'activated':
    case 'exhausted':
      return EsimStage.inUse;
    case 'expired':
      return EsimStage.expired;
    default:
      return EsimStage.purchased;
  }
}

/// Share of data left, 0 to 1, or null when it cannot be shown.
double? remainingDataFraction({
  required int? remainingMb,
  required int? totalMb,
  required bool isUnlimited,
}) {
  if (isUnlimited || remainingMb == null || totalMb == null || totalMb <= 0) {
    return null;
  }
  return (remainingMb / totalMb).clamp(0.0, 1.0);
}

class EsimSections {
  const EsimSections({
    required this.active,
    required this.expired,
    required this.archived,
  });

  final List<OwnedEsim> active;
  final List<OwnedEsim> expired;
  final List<OwnedEsim> archived;

  bool get isEmpty => active.isEmpty && expired.isEmpty && archived.isEmpty;
}

class ParsedLpa {
  const ParsedLpa({required this.smdpAddress, required this.activationCode});

  final String smdpAddress;
  final String activationCode;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int _timeMs(String? iso) {
  if (iso == null || iso.isEmpty) {
    return 0;
  }
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
}

int _newestFirst(OwnedEsim a, OwnedEsim b) {
  final byIssued =
      _timeMs(b.issuedAt ?? b.createdAt) - _timeMs(a.issuedAt ?? a.createdAt);
  if (byIssued != 0) {
    return byIssued;
  }
  return b.id - a.id;
}

/// Same groups as the web `partitionMyEsims`.
EsimSections partitionEsims(List<OwnedEsim> esims) {
  final active = <OwnedEsim>[];
  final expired = <OwnedEsim>[];
  final archived = <OwnedEsim>[];
  for (final esim in esims) {
    if (esim.archivedAt != null) {
      archived.add(esim);
    } else if (esim.status == 'expired') {
      expired.add(esim);
    } else {
      active.add(esim);
    }
  }
  active.sort(_newestFirst);
  expired.sort((a, b) {
    final byExpiry = _timeMs(b.usageExpiredAt) - _timeMs(a.usageExpiredAt);
    if (byExpiry != 0) {
      return byExpiry;
    }
    return _newestFirst(a, b);
  });
  archived.sort((a, b) {
    final byArchived = _timeMs(b.archivedAt) - _timeMs(a.archivedAt);
    if (byArchived != 0) {
      return byArchived;
    }
    return b.id - a.id;
  });
  return EsimSections(active: active, expired: expired, archived: archived);
}

String formatEsimStatus(String status) {
  final trimmed = status.trim();
  if (trimmed.isEmpty) {
    return 'eSIM';
  }
  return trimmed
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String esimUsageLine(OwnedEsim esim) {
  final usage = esim.usageIsUnlimited
      ? 'Unlimited'
      : (esim.usageRemainingMb == null || esim.usageTotalMb == null)
      ? 'Usage not synced'
      : '${esim.usageRemainingMb} / ${esim.usageTotalMb} MB';
  final data = esim.dataAllowance.trim();
  if (data.isEmpty) {
    return usage;
  }
  return '$data · $usage';
}

ParsedLpa? parseLpa(String lpa) {
  final raw = lpa.trim();
  if (raw.isEmpty) {
    return null;
  }
  final body = raw
      .replaceFirst(RegExp(r'^LPA:', caseSensitive: false), '')
      .trim();
  final parts = body.split(r'$');
  if (parts.length >= 3) {
    return ParsedLpa(
      smdpAddress: parts[1].trim(),
      activationCode: parts[2].trim(),
    );
  }
  final host =
      !body.contains(r'$') &&
      !RegExp(r'\s').hasMatch(body) &&
      body.contains('.');
  if (host) {
    return ParsedLpa(smdpAddress: body, activationCode: '');
  }
  return const ParsedLpa(smdpAddress: '', activationCode: '');
}

String? buildLpaUri(String smdpAddress, String activationCode) {
  final smdp = smdpAddress.trim();
  final code = activationCode.trim();
  if (smdp.isEmpty || code.isEmpty) {
    return null;
  }
  return 'LPA:1\$$smdp\$$code';
}

String? resolveLpaUri({String? lpa, String? activationCode}) {
  final existing = lpa?.trim() ?? '';
  if (existing.isNotEmpty) {
    final parsed = parseLpa(existing);
    if (parsed != null &&
        parsed.smdpAddress.isNotEmpty &&
        parsed.activationCode.isNotEmpty) {
      return RegExp(r'^LPA:', caseSensitive: false).hasMatch(existing)
          ? existing
          : 'LPA:$existing';
    }
    if (parsed != null && parsed.smdpAddress.isNotEmpty) {
      final fromHost = buildLpaUri(parsed.smdpAddress, activationCode ?? '');
      if (fromHost != null) {
        return fromHost;
      }
    }
  }
  return null;
}

/// GSMA code passed to Android, without the `LPA:` prefix.
String? androidActivationCode({String? lpa, String? matchingId}) {
  final uri = resolveLpaUri(lpa: lpa, activationCode: matchingId);
  if (uri == null) {
    return null;
  }
  return uri.replaceFirst(RegExp(r'^LPA:', caseSensitive: false), '');
}

/// Google universal link that opens Android eSIM setup with the code filled in.
String? androidSetupLink({String? lpa, String? matchingId}) {
  return _setupLink(
    host: 'esimsetup.android.com',
    lpa: lpa,
    matchingId: matchingId,
  );
}

/// Apple universal link that opens iOS eSIM setup with the code filled in.
String? appleSetupLink({String? lpa, String? matchingId}) {
  return _setupLink(
    host: 'esimsetup.apple.com',
    lpa: lpa,
    matchingId: matchingId,
  );
}

String? _setupLink({required String host, String? lpa, String? matchingId}) {
  final code = androidActivationCode(lpa: lpa, matchingId: matchingId);
  if (code == null || code.isEmpty) {
    return null;
  }
  final carddata = Uri.encodeComponent('LPA:$code');
  return 'https://$host/esim_qrcode_provisioning?carddata=$carddata';
}
