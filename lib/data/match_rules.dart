/// How Schap recognises its products in a supermarket's assortment. Shared
/// by tool/sync_prices.dart (Checkjebon data) and the Picnic link (search
/// results), so every store is matched by the same rules.
library;

import 'brand_catalog.dart';

/// How one Schap product is recognised in a supermarket's assortment.
class Rule {
  final String id;

  /// Every word must occur in the product name.
  final List<String> all;

  /// At least one must occur (empty = no constraint).
  final List<String> any;

  /// None may occur.
  final List<String> not;

  /// Pack size in base units (ml, g or pieces) and the allowed deviation.
  /// Size 0 accepts any pack (loose produce, bread).
  final double size, tol;
  const Rule(
    this.id,
    this.all,
    this.size, {
    this.any = const [],
    this.not = const [],
    this.tol = .12,
    this.exact,
    this.minSize = 0,
  });

  /// Smallest acceptable pack when [size] is 0 (loose produce): keeps a
  /// single banana from passing as a bunch.
  final double minSize;

  /// For brand products: the normalised name (see [normName]) that must
  /// match exactly. Sold under the same name and size at every chain.
  final String? exact;
}

const _flavours = [
  'bio', 'lactosevrij', 'lactose', 'houdbaar', 'houdbare', 'mini', 'light', //
  'vanille', 'honing', 'aardbei', 'kokos', 'chocola', 'geit', 'baby', 'kind',
];

/// Hand-written rules for staples, whose names differ per chain.
const handRules = <Rule>[
  Rule(
    'melk',
    ['halfvolle', 'melk'],
    1000,
    not: [
      ..._flavours,
      'melkunie',
      'yoghurt',
      'kwark',
      'koffiemelk',
      'karne',
      'poeder',
      'drink',
      'x',
      'choco',
      'calcium',
    ],
  ),
  Rule('havermelk', ['oatly', 'barista'], 1000, not: ['x ']),
  Rule(
    'eieren',
    ['scharrel', 'eier'],
    10,
    tol: .25,
    not: ['advocaat', 'bio', 'gekookt', 'salade', 'kwartel'],
  ),
  Rule(
    'yoghurt',
    ['griekse', 'yoghurt'],
    1000,
    not: [
      'vanille',
      'aardbei',
      'perzik',
      'honing',
      'kokos',
      '0%',
      '0,1%',
      '2%',
      'drink',
      'bio',
    ],
  ),
  Rule(
    'kaas',
    ['jong', 'belegen', 'plak'],
    400,
    tol: .4,
    not: ['bio', '30+', '35+', 'geit', 'komijn', 'light', 'extra'],
  ),
  Rule(
    'boter',
    ['roomboter'],
    250,
    any: ['ongezouten'],
    not: ['plantaardige', 'bio', 'halfvol'],
  ),
  Rule('brood', ['volkoren', 'heel'], 0, not: ['bio', 'spelt', 'half']),
  Rule(
    'bananen',
    ['bananen'],
    0,
    minSize: 500,
    not: [
      'bio',
      'pudding',
      'smaak',
      'chips',
      'gedroogd',
      'bak',
      'mini',
      'kind',
      'later',
      'ready',
      'pancake',
      'knijp',
      'vries',
      'gesuikerd',
      'aardbei',
      '200 g',
    ],
  ),
  Rule('appels', ['elstar'], 1500, tol: .4, not: ['bio', 'sap', 'moes']),
  Rule(
    'tomaten',
    ['tros', 'toma'],
    500,
    not: [
      'bio',
      'cocktail',
      'cherry',
      'snoep',
      'soep',
      'honing',
      'mini',
      'finest',
    ],
  ),
  Rule(
    'komkommer',
    ['komkommer'],
    1,
    tol: .01,
    not: [
      'bio',
      'snack',
      'mini',
      'salade',
      'zuur',
      'schijf',
      'half',
      'water',
      'spa',
      'augurk',
      'drink',
      'tonic',
      'limonade',
    ],
  ),
  Rule(
    'paprika',
    ['paprika'],
    3,
    any: ['mix', 'rood geel groen', 'stoplicht', 'trio'],
    tol: .01,
    not: [
      'bio',
      'chips',
      'poeder',
      'puntpaprika',
      'snack',
      'gegrild',
      'saus',
      'spread',
    ],
  ),
  Rule(
    'spinazie',
    ['spinazie'],
    400,
    tol: .15,
    not: [
      'bio',
      'blad',
      'room',
      'creme',
      'crème',
      'gehakt',
      'hak ',
      'knorr',
      'pasta',
      'tortell',
      'lasagne',
      'penne',
      'kip',
    ],
  ),
  Rule(
    'aardappel',
    ['aardappel', 'kruimig'],
    3000,
    not: ['bio', 'zoete', 'puree', 'iets', 'stamppot', 'rood'],
  ),
  Rule(
    'ui',
    ['uien'],
    1000,
    tol: .01,
    not: [
      'bio',
      'rode',
      'gebakken',
      'zilver',
      'bos',
      'lente',
      'gesneden',
      'zoete',
      'ringen',
      'sjalot',
      'amsterdam',
      'witte',
    ],
  ),
  Rule(
    'kip',
    ['kipfilet'],
    475,
    tol: .2,
    not: [
      'bio',
      'gerookt',
      'plak',
      'gegrild',
      'reepjes',
      'haas',
      'gemarineerd',
      'beleg',
      'salade',
      'schnitzel',
      'kat',
      'hond',
      'saus',
      'spies',
      'gekruid',
      'dun',
      'wortel',
      'erwt',
      'iglo',
      'krokant',
      'ovenschotel',
      'meal',
      'spinazie',
      'gepaneerd',
      'chili',
      'provence',
    ],
  ),
  Rule(
    'gehakt',
    ['rundergehakt'],
    500,
    tol: .01,
    not: ['bio', 'mager', 'minder', 'half', 'gekruid', 'bal', 'burger'],
  ),
  Rule(
    'zalm',
    ['zalmfilet'],
    250,
    tol: .15,
    not: [
      'bio',
      'gerookt',
      'diepvries',
      'wilde',
      'kat',
      'hond',
      'gemarineerd',
      'salade',
      'moot',
      'pesto',
      'kruiden',
      'pasta',
      'plantaardig',
      'vivera',
      'limoen',
      'knoflook',
      'bbq',
      'minute',
    ],
  ),
  Rule(
    'tofu',
    ['tofu'],
    420,
    tol: .15,
    not: [
      'gerookt',
      'blokjes',
      'gemarineerd',
      'gyoza',
      'maaltijd',
      'teriyaki',
      'reepjes',
      'roerbak',
    ],
  ),
  Rule(
    'kikkererwten',
    ['kikkererwten'],
    400,
    tol: .15,
    not: [
      'bio',
      'curry',
      'chips',
      'pasta',
      'salade',
      'gedroogd',
      'meel',
      'geroosterd',
      'saus',
      'x',
      'pot',
      'snack',
      'burger',
    ],
  ),
  Rule('pasta', ['penne', 'volkoren'], 500, not: ['bio', 'glutenvrij']),
  Rule(
    'rijst',
    ['basmati'],
    1000,
    not: [
      'bio',
      'tilda',
      'zilvervlies',
      'meergranen',
      'builtjes',
      'kook',
      'x',
      'voorgekookt',
      'magnetron',
      'minuten',
    ],
  ),
  Rule(
    'passata',
    ['passata'],
    500,
    tol: .25,
    not: ['bio', 'basilicum', 'knoflook', 'x', 'kruiden', 'mutti'],
  ),
  Rule(
    'havermout',
    ['havermout'],
    500,
    not: [
      'bio',
      'brinta',
      'quaker',
      'glutenvrij',
      'pap',
      'koek',
      'reep',
      'drink',
      'x',
      'fijn',
      'banaan',
      'appel',
      'instant',
    ],
  ),
  Rule(
    'koffie',
    ['douwe egberts', 'aroma rood'],
    500,
    any: ['filterkoffie', 'snelfiltermaling'],
    not: [
      'bonen',
      'pads',
      'cups',
      'grove',
      'donker',
      'x',
      'cafeinevrij',
      'cafeïnevrij',
      'decaf',
      'dubbelpak',
    ],
  ),
  Rule(
    'pindakaas',
    ['calv', 'pindakaas'],
    650,
    tol: .1,
    not: ['stukjes', 'light', '100%', 'naturel', 'kids', 'grof', 'knijp', 'x'],
  ),
  Rule(
    'olijfolie',
    ['bertolli', 'olijfolie'],
    500,
    any: ['extra vierge', 'extra vergine', 'originale'],
    not: ['spray', 'robusto', 'fruttato', 'gentile', 'bio', 'mild', 'knijp'],
  ),
  Rule(
    'cola',
    ['coca', 'cola', 'zero'],
    1500,
    tol: .01,
    not: ['cherry', 'lime', 'vanilla', 'caffe', 'cafe', 'lemon'],
  ),
  Rule(
    'wcpapier',
    ['page'],
    16,
    any: ['toiletpapier', 'wc-papier', 'wc papier', 'voordeelpak'],
    tol: .01,
    not: ['vochtig'],
  ),
  Rule('wasmiddel', ['ariel', 'pods'], 15, tol: .01, not: ['vaatwas']),
  Rule(
    'vaatwas',
    ['finish'],
    40,
    any: ['tabs', 'tabletten', 'capsules'],
    tol: .25,
    not: ['machinereiniger', 'zout', 'spoelglans', 'verfrisser'],
  ),
];

/// Schap store id → dataset code.
final _mult = RegExp(
  r'(\d+)\s*x\s*(\d+(?:[.,]\d+)?)\s*(kg|kilo|gram|gr|g|liter|ltr|lt|l|ml|cl|stuks|stuk|st|rollen|tabs|pods)\b',
);
final _single = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(kg|kilo|gram|gr|g|liter|ltr|lt|l|ml|cl|stuks|stuk|st|rollen|rol|tabs|tabletten|pods|wasbeurten|capsules)\b',
);

double unitFactor(String u) => switch (u) {
  'kg' || 'kilo' || 'liter' || 'ltr' || 'lt' || 'l' => 1000,
  'cl' => 10,
  _ => 1,
};

/// Pack size in ml, g or pieces; null when the text names none.
double? packSize(String text) {
  final t = text.toLowerCase();
  final m = _mult.firstMatch(t);
  if (m != null) {
    return int.parse(m[1]!) *
        double.parse(m[2]!.replaceAll(',', '.')) *
        unitFactor(m[3]!);
  }
  if (t.contains('per stuk')) return 1;
  final s = _single.firstMatch(t);
  if (s == null) return null;
  return double.parse(s[1]!.replaceAll(',', '.')) * unitFactor(s[2]!);
}

Map<String, dynamic>? match(Rule r, List products) {
  Map<String, dynamic>? best;
  for (final raw in products) {
    final p = raw as Map<String, dynamic>;
    final name = (p['n'] as String).toLowerCase();
    if (r.exact != null && normName(p['n'] as String) != r.exact) continue;
    if (!r.all.every(name.contains)) continue;
    if (r.any.isNotEmpty && !r.any.any(name.contains)) continue;
    if (r.not.any(name.contains)) continue;
    final price = (p['p'] as num?)?.toDouble();
    if (price == null || price <= 0) continue;
    final size = packSize('${p['s'] ?? ''}') ?? packSize(name);
    if (r.minSize > 0 && size != null && size < r.minSize) continue;
    if (r.size > 0 &&
        (size == null || (size - r.size).abs() > r.size * r.tol + 1e-9)) {
      continue;
    }
    if (best == null || price < (best['p'] as num)) {
      best = {'p': price, 'n': p['n'], 's': p['s'] ?? '', 'l': p['l'] ?? ''};
    }
  }
  return best;
}

/// Every rule: the staples plus the brand catalogue.
final rules = <Rule>[
  ...handRules,
  for (final b in brandItems)
    Rule(b.id, const [], b.size, tol: .02, exact: b.key),
];

final _sizeText = RegExp(
  r'(?:(\d+)\s*x\s*)?(\d+(?:[.,]\d+)?)\s*(kg|kilo|gram|gr|g|liter|ltr|lt|l|ml|cl|stuks|stuk|st|rollen|rol|tabs|tabletten|pods|capsules|wasbeurten)\b',
);
final _notWord = RegExp(r"[^a-z0-9éèëïöüç' ]");

/// Lower case, pack size removed, punctuation to spaces. Must stay identical
/// to `norm` in tool/gen_brand_catalog.py.
String normName(String name) => name
    .toLowerCase()
    .replaceAll(_sizeText, ' ')
    .replaceAll(_notWord, ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');
