// Reads shelf prices and promotions from the product pages of jumbo.com and
// hoogvliet.nl. Pure functions over the page HTML, so they can be checked
// against saved pages; tool/sync_prices.dart does the fetching.
//
// Accuracy over coverage: a promotion is only returned when the store states
// a price for buying ONE of this product, now, in the shop. Multi-buys
// ("2 voor 3,00", "1+1 gratis"), per-weight prices, mix-and-match and
// online-only offers are skipped rather than converted.
import 'dart:convert';

double _fromCents(num c) => c.round() / 100;
double _round(double v) => (v * 100).round() / 100;
double? _euro(String s) => double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));

// ---------------------------------------------------------------- Jumbo

/// Nuxt's devalue payload: a flat array where object values and array items
/// are indexes into the array. Resolves one index into plain Dart values.
class _Devalue {
  _Devalue(this.a);
  final List a;
  final _memo = <int, Object?>{};
  static const _wrappers = {
    'ShallowReactive', 'Reactive', 'Ref', 'ShallowRef', 'EmptyRef', //
    'EmptyShallowRef',
  };

  Object? at(Object? i) {
    if (i is! int) return i;
    if (i < 0 || i >= a.length) return null; // -1 undefined, -2 hole, ...
    if (_memo.containsKey(i)) return _memo[i];
    final v = a[i];
    if (v is List) {
      if (v.isNotEmpty && v.first is String) {
        final tag = v.first as String;
        final out = _wrappers.contains(tag) && v.length > 1 ? at(v[1]) : null;
        return _memo[i] = out; // Date, Set, Map, ... are not needed here
      }
      final out = <Object?>[];
      _memo[i] = out;
      for (final x in v) {
        out.add(at(x));
      }
      return out;
    }
    if (v is Map) {
      final out = <String, Object?>{};
      _memo[i] = out;
      v.forEach((k, x) => out['$k'] = at(x));
      return out;
    }
    return _memo[i] = v;
  }
}

final _nuxtData = RegExp(
  r'<script type="application/json"[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>',
  dotAll: true,
);

/// Every top-level-resolvable object in the payload with this `__typename`.
List<Map<String, Object?>> _nuxtObjects(String html, String typename) {
  final m = _nuxtData.firstMatch(html);
  if (m == null) return const [];
  final List raw;
  try {
    raw = jsonDecode(m[1]!) as List;
  } catch (_) {
    return const [];
  }
  final d = _Devalue(raw);
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < raw.length; i++) {
    final v = raw[i];
    if (v is Map && v.containsKey('__typename') && d.at(v['__typename']) == typename) {
      out.add(d.at(i) as Map<String, Object?>);
    }
  }
  return out;
}

/// SKU at the end of a jumbo.com product URL, e.g. 429185FLS.
String? jumboSku(String url) =>
    RegExp(r'-(\d+[A-Z]+)/?$').firstMatch(url)?[1];

class JumboPromoRef {
  JumboPromoRef(this.id, this.url, this.tags, {this.mixed = false});
  final String id;
  final String? url;
  final List<String> tags; // non-inverse tag texts, e.g. "voor 1,00"
  final bool mixed; // kies & mix or volume discounts
}

class JumboProduct {
  JumboProduct(this.shelf, this.promoPrice, this.promotions);
  final double shelf;
  final double? promoPrice;
  final List<JumboPromoRef> promotions;
}

/// The product with this SKU on its own product page.
JumboProduct? parseJumboProduct(String html, String sku) {
  for (final p in _nuxtObjects(html, 'Product')) {
    if (p['id'] != sku) continue;
    final price = p['price'];
    if (price is! Map || price['price'] is! num) return null;
    final promo = price['promoPrice'];
    final refs = <JumboPromoRef>[];
    for (final pr in (p['promotions'] as List? ?? const [])) {
      if (pr is! Map || pr['id'] == null) continue;
      final tags = [
        for (final t in (pr['tags'] as List? ?? const []))
          if (t is Map && t['inverse'] != true && t['text'] is String)
            (t['text'] as String).trim(),
      ];
      refs.add(JumboPromoRef(
        '${pr['id']}',
        pr['url'] as String?,
        tags,
        mixed: pr['isKiesAndMix'] == true ||
            (pr['volumeDiscounts'] as List? ?? const []).isNotEmpty,
      ));
    }
    return JumboProduct(
      _fromCents(price['price'] as num),
      promo is num ? _fromCents(promo) : null,
      refs,
    );
  }
  return null;
}

class JumboPromotion {
  JumboPromotion(this.start, this.end, this.endIso, this.subtitle,
      {required this.live});
  final DateTime start, end;
  final String endIso;
  final String subtitle;
  final bool live; // active and not hidden
}

/// The promotion with this id on its /aanbiedingen/<slug>/<id> page.
JumboPromotion? parseJumboPromotion(String html, String id) {
  for (final p in _nuxtObjects(html, 'Promotion')) {
    if (p['id'] != id) continue;
    final s = (p['start'] as Map?)?['iso'], e = (p['end'] as Map?)?['iso'];
    if (s is! String || e is! String) continue; // the short variant
    final start = DateTime.tryParse(s), end = DateTime.tryParse(e);
    if (start == null || end == null) return null;
    return JumboPromotion(
      start,
      end,
      e,
      '${p['subtitle'] ?? ''}'.replaceAll(RegExp(r'<br\s*/?>'), ' '),
      live: p['active'] == true && p['hidden'] != true,
    );
  }
  return null;
}

// Per-weight or multi-unit wording: the stated price is not for one pack.
final _jumboSubtitleBlock = RegExp(
  r'per\s+\d+\s*(gram|gr|g|kilo|kg|ml|cl|liter|l)\b|per\s+(kilo|kg|liter)\b'
  r'|\b\d+\s*x\s*\d',
  caseSensitive: false,
);

/// The deal for one unit, or null when the promotion does not qualify.
Map<String, Object>? jumboDeal(
  JumboProduct product,
  JumboPromoRef ref,
  JumboPromotion promo,
  DateTime now,
) {
  if (ref.mixed || !promo.live || ref.tags.length != 1) return null;
  if (now.isBefore(promo.start) || now.isAfter(promo.end)) return null;
  final shelf = product.shelf;
  final tag = ref.tags.single;
  double? p;
  RegExpMatch? m;
  if ((m = RegExp(r'^(?:voor\s+)?(\d+,\d{2})$', caseSensitive: false)
          .firstMatch(tag)) !=
      null) {
    p = _euro(m![1]!);
  } else if ((m = RegExp(r'^(\d{1,2})%\s*korting$', caseSensitive: false)
          .firstMatch(tag)) !=
      null) {
    p = _round(shelf * (1 - int.parse(m![1]!) / 100));
  } else if ((m = RegExp(r'^(\d+,\d{2})\s*korting$', caseSensitive: false)
          .firstMatch(tag)) !=
      null) {
    p = _round(shelf - _euro(m![1]!)!);
  }
  if (p == null) return null;
  final promoPrice = product.promoPrice;
  if (promoPrice != null && (promoPrice - p).abs() > .011) return null;
  // Per-weight or multi-unit wording makes the tag ambiguous, unless Jumbo
  // also states this SKU's own promo price and it agrees with the tag.
  if (promoPrice == null && _jumboSubtitleBlock.hasMatch(promo.subtitle)) {
    return null;
  }
  if (p >= shelf || p < shelf * .25) return null;
  return {'label': tag, 'p': p, 'end': promo.endIso.substring(0, 10)};
}

// ------------------------------------------------------------ Hoogvliet

final _nextData = RegExp(
  r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
  dotAll: true,
);

class HoogvlietProduct {
  HoogvlietProduct(this.shelf, this.deal);
  final double shelf;
  final Map<String, Object>? deal;
}

final _hvLabelBlock = RegExp(
  r'gratis|\d+\s*voor|halve|per\s+\d+\s*(gram|gr|g|kilo|kg|ml)\b'
  r'|per\s+(kilo|kg)\b|bezorg|\+',
  caseSensitive: false,
);

/// Shelf price and (if it qualifies) the current promotion on a
/// hoogvliet.nl product page.
HoogvlietProduct? parseHoogvliet(String html, DateTime now) {
  final m = _nextData.firstMatch(html);
  if (m == null) return null;
  Map e;
  try {
    e = (jsonDecode(m[1]!) as Map)['props']['pageProps']['entity'] as Map;
  } catch (_) {
    return null;
  }
  final range = (e['price_range'] as Map?)?['minimum_price'] as Map?;
  final regular = ((range?['regular_price'] as Map?)?['value'] as num?)
      ?.toDouble();
  final fin = ((range?['final_price'] as Map?)?['value'] as num?)?.toDouble();
  if (regular == null || regular <= 0) return null;
  return HoogvlietProduct(regular, _hoogvlietDeal(e, regular, fin, now));
}

Map<String, Object>? _hoogvlietDeal(
    Map e, double regular, double? fin, DateTime now) {
  if (e['is_promotion'] != true || e['is_promotion_online_only'] == true) {
    return null;
  }
  if (fin == null || fin >= regular || fin < regular * .25) return null;
  final meta = e['promotion_meta_data'];
  if (meta is! Map) return null;
  final from = DateTime.tryParse('${meta['valid_from']}');
  final to = DateTime.tryParse('${meta['valid_to']}');
  if (from == null || to == null || now.isBefore(from) || now.isAfter(to)) {
    return null;
  }
  final label = '${meta['korting_label'] ?? e['discount_label'] ?? ''}'
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (label.isEmpty || _hvLabelBlock.hasMatch(label)) return null;
  final pct = RegExp(r'^(\d{1,2})%\s*korting$', caseSensitive: false)
      .firstMatch(label);
  if (pct != null) {
    final expect = regular * (1 - int.parse(pct[1]!) / 100);
    if ((expect - fin).abs() > .011) return null;
  } else {
    // "per pak 1,99": the price in the label must be the price we publish.
    final raw = (meta['raw_discount_label'] as Map?)?['price'];
    if (raw is! num || (raw - fin).abs() > .001) return null;
    if (!RegExp(r'^per [a-z]+ \d+,\d{2}$', caseSensitive: false)
        .hasMatch(label)) {
      return null;
    }
  }
  return {'label': label, 'p': _round(fin), 'end': amsterdamDate(to)};
}

/// Calendar date in Europe/Amsterdam (CET, CEST from the last Sunday of
/// March to the last Sunday of October, switching at 01:00 UTC).
String amsterdamDate(DateTime t) {
  final u = t.toUtc();
  DateTime lastSunday(int month) {
    var d = DateTime.utc(u.year, month + 1, 0, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final summer = !u.isBefore(lastSunday(3)) && u.isBefore(lastSunday(10));
  return u.add(Duration(hours: summer ? 2 : 1)).toIso8601String().substring(0, 10);
}
