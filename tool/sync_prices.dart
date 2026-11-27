// Pulls current shelf prices from the Checkjebon open dataset and writes the
// slice Schap needs to assets/prices.json.
//
//   dart run tool/sync_prices.dart            # download and write
//   dart run tool/sync_prices.dart file.json  # use a local copy
//   dart run tool/sync_prices.dart -v         # also print every match
//
// Source: https://github.com/supermarkt/checkjebon (MIT, "may be reused in
// other projects"). The dataset holds regular shelf prices only: no
// promotions, and no data for Picnic or ALDI; promotions come from AH, Jumbo
// and Hoogvliet themselves (see enrich* and tool/promotions.dart). In production this script runs
// on a server on a schedule and the app fetches the result.
import 'dart:convert';
import 'dart:io';
import 'package:schap/data/match_rules.dart';
import 'promotions.dart';

const source =
    'https://raw.githubusercontent.com/supermarkt/checkjebon/main/data/supermarkets.json';

const storeCodes = {
  'ah': 'ah', 'jumbo': 'jumbo', 'picnic': 'picnic', 'plus': 'plus', //
  'lidl': 'lidl', 'aldi': 'aldi', 'dirk': 'dirk', 'hoogvliet': 'hoogvliet',
  'vomar': 'vomar', 'dekamarkt': 'dekamarkt', 'spar': 'spar',
  'poiesz': 'poiesz',
};

/// Product page on the supermarket's own site, from the dataset's link slug.
String? productUrl(String store, String slug) => switch (store) {
  'ah' => 'https://www.ah.nl/producten/product/$slug',
  'jumbo' => 'https://www.jumbo.com/producten/$slug',
  'hoogvliet' => 'https://www.hoogvliet.com/product/$slug',
  'plus' => 'https://www.plus.nl/product/$slug',
  'dirk' => 'https://www.dirk.nl/boodschappen/x/x/$slug',
  _ => null,
};

const _browser =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';
final _http = HttpClient()..connectionTimeout = const Duration(seconds: 12);

Future<String?> _get(String url, Map<String, String> headers) async {
  try {
    final req = await _http.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    return res.statusCode == 200 ? body : null;
  } catch (_) {
    return null;
  }
}

/// Albert Heijn: current price, real Bonus promotion and photo, read from the
/// catalogue search its own app uses. No login; unofficial, so it can change
/// or be blocked without notice and every field is treated as optional.
Future<void> enrichAh(Map<String, dynamic> hits) async {
  String? token;
  try {
    final req = await _http.postUrl(
      Uri.parse('https://api.ah.nl/mobile-auth/v1/auth/token/anonymous'),
    );
    req.headers.set('content-type', 'application/json');
    req.headers.set('user-agent', 'Appie/8.22.3');
    req.write(jsonEncode({'clientId': 'appie'}));
    final res = await req.close();
    token =
        jsonDecode(await res.transform(utf8.decoder).join())['access_token']
            as String?;
  } catch (_) {}
  if (token == null) {
    stdout.writeln('  ah: no anonymous token, keeping dataset prices');
    return;
  }
  var n = 0;
  for (final hit in hits.values) {
    final name = hit['n'] as String;
    final body = await _get(
      'https://api.ah.nl/mobile-services/product/search/v2'
      '?query=${Uri.encodeQueryComponent(name)}&sortOn=RELEVANCE&size=8',
      {
        'authorization': 'Bearer $token',
        'user-agent': 'Appie/8.22.3',
        'x-application': 'AHWEBSHOP',
      },
    );
    if (body == null) continue;
    final list = (jsonDecode(body)['products'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final p = list
        .where((p) => '${p['title']}'.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (p == null) continue;
    n++;
    final before = (p['priceBeforeBonus'] as num?)?.toDouble();
    final now = (p['currentPrice'] as num?)?.toDouble();
    if (before != null) hit['p'] = before;
    final images = (p['images'] as List? ?? []).cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['width'] as num? ?? 0).compareTo(b['width'] ?? 0));
    final img = images.where((i) => (i['width'] as num? ?? 0) >= 200);
    if (images.isNotEmpty) {
      hit['img'] = (img.isNotEmpty ? img.first : images.last)['url'];
    }
    if (p['isBonus'] == true && before != null && now != null && now < before) {
      hit['deal'] = {
        'label': p['bonusMechanism'] ?? 'Bonus',
        'p': now,
        'end': p['bonusEndDate'],
      };
    }
  }
  stdout.writeln('  ah: $n/${hits.length} enriched from the AH catalogue');
}

final _og = RegExp(
  r'''<meta[^>]*(?:content="([^"]+)"[^>]*property="og:image"|property="og:image"[^>]*content="([^"]+)")''',
);

String? _ogImage(String html) {
  final m = _og.firstMatch(html);
  final img = m?[1] ?? m?[2];
  return img == null || img.contains('logo') || img.contains('footer')
      ? null
      : img;
}

/// Jumbo: shelf price, photo and the promotion Jumbo states on the product
/// page. The promotion's own page gives its exact start and end.
Future<void> enrichJumbo(Map<String, dynamic> hits) async {
  final now = DateTime.now().toUtc();
  final promoPages = <String, JumboPromotion?>{};
  var photos = 0, priced = 0, deals = 0;
  for (final hit in hits.values) {
    final url = hit['u'] as String?;
    final sku = url == null ? null : jumboSku(url);
    if (url == null) continue;
    final html = await _get(url, {'user-agent': _browser});
    if (html == null) continue;
    final img = _ogImage(html);
    if (img != null) {
      hit['img'] = img;
      photos++;
    }
    final product = sku == null ? null : parseJumboProduct(html, sku);
    if (product == null) continue;
    hit['p'] = product.shelf;
    priced++;
    for (final ref in product.promotions) {
      if (ref.url == null) continue;
      final promo = promoPages.containsKey(ref.id)
          ? promoPages[ref.id]
          : promoPages[ref.id] = await _get(
              'https://www.jumbo.com${ref.url}',
              {'user-agent': _browser},
            ).then((h) => h == null ? null : parseJumboPromotion(h, ref.id));
      final deal = promo == null ? null : jumboDeal(product, ref, promo, now);
      if (deal != null) {
        hit['deal'] = deal;
        deals++;
        break;
      }
    }
  }
  stdout.writeln(
    '  jumbo: $priced/${hits.length} priced, $photos photos, $deals deals',
  );
}

/// Hoogvliet: shelf price, photo and the current promotion from the product
/// page (www.hoogvliet.com redirects to hoogvliet.nl).
Future<void> enrichHoogvliet(Map<String, dynamic> hits) async {
  final now = DateTime.now().toUtc();
  var photos = 0, priced = 0, deals = 0;
  for (final hit in hits.values) {
    final url = hit['u'] as String?;
    if (url == null) continue;
    final html = await _get(url, {'user-agent': _browser});
    if (html == null) continue;
    final img = _ogImage(html);
    if (img != null) {
      hit['img'] = img;
      photos++;
    }
    final product = parseHoogvliet(html, now);
    if (product == null) continue;
    hit['p'] = product.shelf;
    priced++;
    if (product.deal != null) {
      hit['deal'] = product.deal;
      deals++;
    }
  }
  stdout.writeln(
    '  hoogvliet: $priced/${hits.length} priced, $photos photos, $deals deals',
  );
}

Future<void> main(List<String> args) async {
  final verbose = args.contains('-v');
  final local = args.where((a) => !a.startsWith('-')).firstOrNull;
  final String body;
  if (local != null) {
    body = await File(local).readAsString();
  } else {
    stdout.writeln('Downloading $source');
    final req = await HttpClient().getUrl(Uri.parse(source));
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('Download failed: HTTP ${res.statusCode}');
      exit(1);
    }
    body = await res.transform(utf8.decoder).join();
  }
  final data = {
    for (final s in jsonDecode(body) as List) s['n'] as String: s['d'] as List,
  };

  final out = <String, Map<String, dynamic>>{};
  storeCodes.forEach((id, code) {
    final products = data[code] ?? const [];
    final hits = <String, dynamic>{};
    for (final r in rules) {
      final m = match(r, products);
      if (m != null) hits[r.id] = m;
      if (verbose) {
        stdout.writeln(
          '  $id ${r.id.padRight(13)} ${m == null ? '—' : '${m['p']}  ${m['n']} (${m['s']})'}',
        );
      }
    }
    stdout.writeln(
      '${id.padRight(10)} ${hits.length.toString().padLeft(2)}/${rules.length} matched'
      '${products.isEmpty ? '  (no data in source)' : ''}',
    );
    // A store is only "live" when most of the staples could be priced; the
    // brand catalogue is too uneven to judge a chain by.
    final staples = handRules.where((r) => hits.containsKey(r.id)).length;
    if (staples >= handRules.length * .6) out[id] = hits;
  });

  for (final e in out.entries) {
    for (final hit in e.value.values) {
      final slug = hit.remove('l') as String? ?? '';
      final url = slug.isEmpty ? null : productUrl(e.key, slug);
      if (url != null) hit['u'] = url;
    }
  }
  if (!args.contains('--no-enrich')) {
    stdout.writeln('Enriching with photos and promotions');
    if (out['ah'] != null) await enrichAh(out['ah']!);
    if (out['jumbo'] != null) await enrichJumbo(out['jumbo']!);
    if (out['hoogvliet'] != null) await enrichHoogvliet(out['hoogvliet']!);
  }
  _http.close(force: true);

  final file = File('assets/prices.json');
  await file.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent(' ').convert({
      'updated': DateTime.now().toUtc().toIso8601String(),
      'source': 'Checkjebon open data, ah.nl, jumbo.com, hoogvliet.nl',
      'stores': out,
    }),
  );
  stdout.writeln(
    'Wrote ${file.path} with ${out.length} live stores: '
    '${out.keys.join(', ')}',
  );
  await _appendHistory(out);
}

/// Keeps one shelf price per store, product and day in
/// assets/price_history.json (120 days), so the app can tell a real
/// promotion from a price that was normal last week.
Future<void> _appendHistory(Map<String, Map<String, dynamic>> out) async {
  final file = File('assets/price_history.json');
  var all = <String, dynamic>{};
  if (await file.exists()) {
    try {
      all = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
  }
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  all[today] = {
    for (final MapEntry(key: store, value: items) in out.entries)
      store: {
        for (final MapEntry(key: id, value: v) in items.entries)
          id: (v as Map)['p'],
      },
  };
  final cutoff = DateTime.now().subtract(const Duration(days: 120));
  all.removeWhere((day, _) => DateTime.tryParse(day)?.isBefore(cutoff) ?? true);
  await file.writeAsString(jsonEncode(all));
  stdout.writeln('History: ${all.length} days in ${file.path}');
}
