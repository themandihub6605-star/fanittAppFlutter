import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';

// Edit-profile inputs: phone with country code (India by default), city
// suggestions (India Post, same as the website) and Indian states.

const Color _req = Color(0xFFF4511E);

Widget _label(BuildContext context, String text, bool isRequired) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
  child: Text.rich(
    TextSpan(text: text, children: [
      if (isRequired) const TextSpan(text: ' *', style: TextStyle(color: _req, fontWeight: FontWeight.w800)),
    ]),
    style: context.text.labelMedium?.copyWith(color: context.palette.textPrimary),
  ),
);

// ---------------------------------------------------------------------------
// Phone with country code
// ---------------------------------------------------------------------------

class CountryCode {
  const CountryCode(this.name, this.flag, this.dial);

  final String name;
  final String flag;
  final String dial; // without "+"

  bool get isIndia => dial == '91';

  static const india = CountryCode('India', '🇮🇳', '91');

  static const all = [
    india,
    CountryCode('United Arab Emirates', '🇦🇪', '971'),
    CountryCode('United States / Canada', '🇺🇸', '1'),
    CountryCode('United Kingdom', '🇬🇧', '44'),
    CountryCode('Australia', '🇦🇺', '61'),
    CountryCode('Singapore', '🇸🇬', '65'),
    CountryCode('Saudi Arabia', '🇸🇦', '966'),
    CountryCode('Qatar', '🇶🇦', '974'),
    CountryCode('Kuwait', '🇰🇼', '965'),
    CountryCode('Oman', '🇴🇲', '968'),
    CountryCode('Bahrain', '🇧🇭', '973'),
    CountryCode('Nepal', '🇳🇵', '977'),
    CountryCode('Bangladesh', '🇧🇩', '880'),
    CountryCode('Sri Lanka', '🇱🇰', '94'),
    CountryCode('Malaysia', '🇲🇾', '60'),
    CountryCode('Germany', '🇩🇪', '49'),
    CountryCode('France', '🇫🇷', '33'),
    CountryCode('New Zealand', '🇳🇿', '64'),
    CountryCode('South Africa', '🇿🇦', '27'),
  ];
}

/// A phone value split into country + local number.
class PhoneValue {
  const PhoneValue(this.country, this.number);

  final CountryCode country;
  final String number; // digits only

  /// Saved format: India → plain 10 digits (same as the website);
  /// other countries → "+<code><number>".
  String get stored => number.isEmpty ? '' : (country.isIndia ? number : '+${country.dial}$number');

  /// Reads a saved phone ("9876543210", "+919876543210", "+971501234567").
  static PhoneValue parse(String? raw) {
    var v = (raw ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (v.startsWith('+')) {
      v = v.substring(1);
      final byLength = [...CountryCode.all]..sort((a, b) => b.dial.length.compareTo(a.dial.length));
      for (final c in byLength) {
        if (v.startsWith(c.dial)) return PhoneValue(c, v.substring(c.dial.length));
      }
      return PhoneValue(CountryCode.india, v);
    }
    if (v.length == 12 && v.startsWith('91')) return PhoneValue(CountryCode.india, v.substring(2));
    if (v.length == 11 && v.startsWith('0')) return PhoneValue(CountryCode.india, v.substring(1));
    return PhoneValue(CountryCode.india, v);
  }

  static String? validate(CountryCode country, String number, {required bool isRequired}) {
    final n = number.trim();
    if (n.isEmpty) return isRequired ? 'Enter your mobile number' : null;
    if (country.isIndia) {
      return RegExp(r'^[6-9]\d{9}$').hasMatch(n) ? null : 'Enter a valid 10-digit mobile number';
    }
    return RegExp(r'^\d{6,14}$').hasMatch(n) ? null : 'Enter a valid phone number';
  }
}

/// Mobile number with a country-code picker (🇮🇳 +91 by default).
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.label = 'Mobile number',
    this.isRequired = false,
  });

  final TextEditingController controller;
  final CountryCode country;
  final ValueChanged<CountryCode> onCountryChanged;
  final String label;
  final bool isRequired;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  Future<void> _pickCountry() async {
    final picked = await showAppSheet<CountryCode>(
      context,
      builder: (ctx) => SheetBody(
        title: 'Country code',
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in CountryCode.all)
                ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                  title: Text(c.name),
                  trailing: Text('+${c.dial}', style: ctx.text.titleSmall),
                  selected: c.dial == widget.country.dial && c.name == widget.country.name,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) widget.onCountryChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.country;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, widget.label, widget.isRequired),
        TextFormField(
          controller: widget.controller,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(c.isIndia ? 10 : 14)],
          style: context.text.bodyLarge?.copyWith(fontSize: 15, color: palette.textPrimary),
          validator: (v) => PhoneValue.validate(c, v ?? '', isRequired: widget.isRequired),
          decoration: InputDecoration(
            hintText: c.isIndia ? '10-digit mobile number' : 'Phone number',
            prefixIconConstraints: const BoxConstraints(minHeight: 44),
            prefixIcon: InkWell(
              onTap: _pickCountry,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text('+${c.dial}', style: context.text.titleSmall),
                    Icon(AppIcons.caretDown, size: 14, color: palette.textSecondary),
                    const SizedBox(width: 6),
                    Container(width: 1, height: 22, color: palette.border),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// City (India Post suggestions) and State (fixed list)
// ---------------------------------------------------------------------------

class CitySuggestion {
  const CitySuggestion(this.city, this.state);

  final String city;
  final String state;
}

/// Looks up towns/cities across India using India Post's free pincode API
/// (the same source the website uses). Debounced, cached, never blocks
/// typing — if it's offline the person just types the city.
abstract final class CityLookup {
  static final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 8)));
  static final Map<String, List<CitySuggestion>> _cache = {};

  static Future<List<CitySuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final key = q.toLowerCase();
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final res = await _dio.get<dynamic>('https://api.postalpincode.in/postoffice/${Uri.encodeComponent(q)}');
      final data = res.data;
      final first = data is List && data.isNotEmpty ? data.first : null;
      final offices = first is Map && first['Status'] == 'Success' && first['PostOffice'] is List ? first['PostOffice'] as List : const [];

      // Districts first (real cities, e.g. "Indore"), then post-office
      // names (towns / areas). Starts-with matches go to the top.
      final seen = <String>{};
      final starts = <CitySuggestion>[];
      final rest = <CitySuggestion>[];
      void add(String city, String state) {
        final c = city.trim();
        if (c.isEmpty || !seen.add('${c.toLowerCase()}|${state.toLowerCase()}')) return;
        (c.toLowerCase().startsWith(key) ? starts : rest).add(CitySuggestion(c, state.trim()));
      }

      for (final o in offices) {
        if (o is! Map) continue;
        final district = (o['District'] ?? '').toString();
        if (district.toLowerCase().contains(key)) add(district, (o['State'] ?? '').toString());
      }
      for (final o in offices) {
        if (o is! Map) continue;
        add((o['Name'] ?? '').toString(), (o['State'] ?? '').toString());
      }
      final list = [...starts, ...rest].take(10).toList();
      _cache[key] = list;
      return list;
    } catch (_) {
      return const [];
    }
  }
}

/// Text field with a suggestion list under it.
class CityField extends StatefulWidget {
  const CityField({
    super.key,
    required this.controller,
    this.label = 'City',
    this.isRequired = false,
    this.onPicked,
    this.hint = 'Start typing your city',
  });

  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final String hint;

  /// Called with the chosen suggestion (e.g. to fill State).
  final ValueChanged<CitySuggestion>? onPicked;

  @override
  State<CityField> createState() => _CityFieldState();
}

class _CityFieldState extends State<CityField> {
  final _focus = FocusNode();
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  bool _justPicked = false;
  List<CitySuggestion> _items = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) setState(() => _items = const []);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_justPicked) {
      _justPicked = false;
      return;
    }
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _items = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final id = ++_request;
      final results = await CityLookup.search(value);
      if (!mounted || id != _request) return; // a newer search is on its way
      setState(() {
        _items = _focus.hasFocus ? results : const [];
        _loading = false;
      });
    });
  }

  void _pick(CitySuggestion s) {
    HapticFeedback.selectionClick();
    _justPicked = true;
    widget.controller.text = s.city;
    widget.controller.selection = TextSelection.collapsed(offset: s.city.length);
    setState(() => _items = const []);
    widget.onPicked?.call(s);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, widget.label, widget.isRequired),
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.words,
          style: context.text.bodyLarge?.copyWith(fontSize: 15, color: palette.textPrimary),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return widget.isRequired ? 'Enter your ${widget.label.toLowerCase()}' : null;
            if (t.length < 2) return 'Enter a valid ${widget.label.toLowerCase()}';
            return null;
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Padding(padding: EdgeInsets.only(left: 14, right: 10), child: Icon(AppIcons.mapPin, size: 20)),
            prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
        if (_items.isNotEmpty) _SuggestionList(items: [for (final s in _items) (title: s.city, subtitle: s.state)], onTap: (i) => _pick(_items[i])),
      ],
    );
  }
}

/// Indian state / UT with suggestions from the fixed 36 list.
class StateField extends StatefulWidget {
  const StateField({super.key, required this.controller, this.isRequired = false});

  final TextEditingController controller;
  final bool isRequired;

  static const states = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana',
    'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur',
    'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana',
    'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ];

  @override
  State<StateField> createState() => _StateFieldState();
}

class _StateFieldState extends State<StateField> {
  final _focus = FocusNode();
  List<String> _items = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() => _items = _focus.hasFocus ? _match(widget.controller.text) : const []);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<String> _match(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return StateField.states.take(8).toList();
    final starts = StateField.states.where((s) => s.toLowerCase().startsWith(t));
    final contains = StateField.states.where((s) => !s.toLowerCase().startsWith(t) && s.toLowerCase().contains(t));
    return [...starts, ...contains].take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, 'State', widget.isRequired),
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => setState(() => _items = _match(v)),
          style: context.text.bodyLarge?.copyWith(fontSize: 15, color: palette.textPrimary),
          validator: (v) => (v?.trim().isEmpty ?? true) ? (widget.isRequired ? 'Enter your state' : null) : null,
          decoration: const InputDecoration(hintText: 'e.g. Madhya Pradesh'),
        ),
        if (_items.isNotEmpty && _focus.hasFocus)
          _SuggestionList(
            items: [for (final s in _items) (title: s, subtitle: '')],
            onTap: (i) {
              final s = _items[i];
              widget.controller.text = s;
              widget.controller.selection = TextSelection.collapsed(offset: s.length);
              setState(() => _items = const []);
              _focus.unfocus();
            },
          ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.onTap});

  final List<({String title, String subtitle})> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: palette.border),
        itemBuilder: (context, i) {
          final it = items[i];
          return InkWell(
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  Icon(AppIcons.mapPin, size: 16, color: palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.title, style: context.text.titleSmall),
                        if (it.subtitle.isNotEmpty) Text(it.subtitle, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}