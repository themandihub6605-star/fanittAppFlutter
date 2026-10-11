import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../data/shop_repository.dart';
import 'shop_widgets.dart';

const indianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir',
  'Jharkhand', 'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
  'Mizoram', 'Nagaland', 'Odisha', 'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
  'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
];

/// Add or edit a delivery address. Pops with the saved [ShopAddress].
class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.address});

  final ShopAddress? address;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.address?.name ?? '');
  late final _phone = TextEditingController(text: widget.address?.phone ?? '');
  late final _pincode = TextEditingController(text: widget.address?.pincode ?? '');
  late final _line1 = TextEditingController(text: widget.address?.line1 ?? '');
  late final _line2 = TextEditingController(text: widget.address?.line2 ?? '');
  late final _landmark = TextEditingController(text: widget.address?.landmark ?? '');
  late final _city = TextEditingController(text: widget.address?.city ?? '');
  late String? _state = indianStates.contains(widget.address?.state) ? widget.address!.state : null;
  late String _label = widget.address?.label ?? 'home';
  late bool _default = widget.address?.isDefault ?? false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _pincode, _line1, _line2, _landmark, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v, String message) => (v == null || v.trim().length < 2) ? message : null;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final saved = await ShopRepository.i.saveAddress(
        {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'pincode': _pincode.text.trim(),
          'line1': _line1.text.trim(),
          'line2': _line2.text.trim(),
          'landmark': _landmark.text.trim(),
          'city': _city.text.trim(),
          'state': _state,
          'label': _label,
          'isDefault': _default,
        },
        id: widget.address?.id,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.address == null ? 'Add delivery address' : 'Edit address')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            AppTextField(
              label: 'Full name',
              isRequired: true,
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (v) => _required(v, 'Enter the full name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Mobile number',
              isRequired: true,
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(16)],
              helperText: 'The delivery partner may call this number',
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                final local = digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
                return RegExp(r'^[6-9]\d{9}$').hasMatch(local) ? null : 'Enter a valid 10-digit mobile number';
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Pincode',
              isRequired: true,
              controller: _pincode,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.postalCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              validator: (v) => RegExp(r'^[1-9]\d{5}$').hasMatch(v ?? '') ? null : 'Enter a valid 6-digit pincode',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'House no., building, street',
              isRequired: true,
              controller: _line1,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().length < 3) ? 'Enter house no. / building / street' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Area, locality', controller: _line2, textCapitalization: TextCapitalization.words),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Landmark (optional)', controller: _landmark, textCapitalization: TextCapitalization.words),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'City / town',
              isRequired: true,
              controller: _city,
              textCapitalization: TextCapitalization.words,
              validator: (v) => _required(v, 'Enter the city'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppDropdown<String>(
              label: 'State',
              isRequired: true,
              items: indianStates,
              value: _state,
              labelOf: (s) => s,
              hint: 'Select state',
              onChanged: (v) => setState(() => _state = v),
              validator: (v) => v == null ? 'Select the state' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Save as'),
            ChoicePills<String>(
              options: const ['home', 'work', 'other'],
              selected: {_label},
              labelOf: (v) => switch (v) { 'work' => 'Work', 'other' => 'Other', _ => 'Home' },
              onChanged: (v) => setState(() => _label = v),
            ),
            const SizedBox(height: AppSpacing.xs),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _default,
              onChanged: (v) => setState(() => _default = v),
              title: Text('Make this my default address', style: context.text.titleSmall),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ShopBottomBar(child: GradientButton(label: 'Save address', isLoading: _saving, onPressed: _save)),
    );
  }
}