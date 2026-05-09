import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'credit_card_vault_page.dart';

// ---------------------------------------------------------------------------
// Input formatters
// ---------------------------------------------------------------------------

/// Formats a raw digit string into groups of 4 separated by spaces.
/// e.g. "4111111111111111" → "4111 1111 1111 1111"
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final buffer = StringBuffer();
    int groupCount = 0;
    for (int i = 0; i < digits.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
        groupCount++;
      }
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formats expiry as MM/YY, auto-inserting the slash after 2 digits.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    String formatted;
    if (digits.length <= 2) {
      formatted = digits;
    } else {
      formatted = '${digits.substring(0, 2)}/${digits.substring(2, digits.length.clamp(0, 4))}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/// Standard Luhn algorithm check.
bool _luhnCheck(String number) {
  final digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 13 || digits.length > 19) return false;

  int sum = 0;
  bool alternate = false;

  for (int i = digits.length - 1; i >= 0; i--) {
    int n = int.parse(digits[i]);
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

/// Validates MM/YY expiry format and logical date.
bool _validExpiry(String s) {
  final parts = s.split('/');
  if (parts.length != 2) return false;

  final mm = int.tryParse(parts[0]);
  final yy = int.tryParse(parts[1]);
  if (mm == null || yy == null) return false;
  if (mm < 1 || mm > 12) return false;

  final now = DateTime.now();
  final currentYear = now.year % 100; // two-digit year
  final currentMonth = now.month;

  if (yy < currentYear) return false;
  if (yy == currentYear && mm < currentMonth) return false;

  return true;
}

// ---------------------------------------------------------------------------
// CardForm widget
// ---------------------------------------------------------------------------

class CardForm extends ConsumerStatefulWidget {
  const CardForm({super.key, this.existingCard});

  /// When non-null, the form is in edit mode.
  final CreditCard? existingCard;

  @override
  ConsumerState<CardForm> createState() => _CardFormState();
}

class _CardFormState extends ConsumerState<CardForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _numberCtrl;
  late final TextEditingController _holderCtrl;
  late final TextEditingController _expiryCtrl;
  late final TextEditingController _cvvCtrl;
  late final TextEditingController _labelCtrl;

  bool _obscureCvv = true;
  bool _isSaving = false;

  bool get _isEditing => widget.existingCard != null;

  @override
  void initState() {
    super.initState();
    final card = widget.existingCard;
    _numberCtrl = TextEditingController(text: card?.formattedNumber ?? '');
    _holderCtrl = TextEditingController(text: card?.holderName ?? '');
    _expiryCtrl = TextEditingController(text: card?.expiry ?? '');
    _cvvCtrl = TextEditingController(text: card?.cvv ?? '');
    _labelCtrl = TextEditingController(text: card?.label ?? '');
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final rawNumber = _numberCtrl.text.replaceAll(' ', '');
      final notifier = ref.read(cardsProvider.notifier);

      if (_isEditing) {
        final updated = widget.existingCard!.copyWith(
          number: rawNumber,
          holderName: _holderCtrl.text.trim(),
          expiry: _expiryCtrl.text.trim(),
          cvv: _cvvCtrl.text.trim(),
          label: _labelCtrl.text.trim(),
        );
        await notifier.update(updated);
      } else {
        final newCard = CreditCard(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          number: rawNumber,
          holderName: _holderCtrl.text.trim(),
          expiry: _expiryCtrl.text.trim(),
          cvv: _cvvCtrl.text.trim(),
          label: _labelCtrl.text.trim(),
        );
        await notifier.add(newCard);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save card: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Validators ───────────────────────────────────────────────────────────

  String? _validateCardNumber(String? value) {
    if (value == null || value.isEmpty) return 'Card number is required';
    final digits = value.replaceAll(' ', '');
    if (digits.length < 13) return 'Card number is too short';
    if (!_luhnCheck(digits)) return 'Invalid card number (Luhn check failed)';
    return null;
  }

  String? _validateHolderName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Cardholder name is required';
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateExpiry(String? value) {
    if (value == null || value.isEmpty) return 'Expiry is required';
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
      return 'Use MM/YY format';
    }
    if (!_validExpiry(value)) return 'Card has expired or invalid month';
    return null;
  }

  String? _validateCvv(String? value) {
    if (value == null || value.isEmpty) return 'CVV is required';
    if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
      return 'CVV must be 3 or 4 digits';
    }
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Cancel',
        ),
        title: Text(
          _isEditing ? 'Edit Card' : 'Add New Card',
          style: AppTheme.textTheme.titleLarge?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.accentBlue,
                    ),
                  )
                : TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _isEditing ? 'Update' : 'Save',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // ── Section: Card Details ─────────────────────────────────
            _SectionHeader(title: 'Card Details'),
            const SizedBox(height: 12),

            // Card number
            _FormField(
              controller: _numberCtrl,
              label: 'Card Number',
              hint: '1234 5678 9012 3456',
              prefixIcon: Icons.credit_card_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _CardNumberFormatter(),
              ],
              maxLength: 19, // 16 digits + 3 spaces
              validator: _validateCardNumber,
              textInputAction: TextInputAction.next,
              fontFamily: 'monospace',
            ),
            const SizedBox(height: 16),

            // Holder name
            _FormField(
              controller: _holderCtrl,
              label: 'Cardholder Name',
              hint: 'JANE DOE',
              prefixIcon: Icons.person_outline_rounded,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.characters,
              validator: _validateHolderName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Expiry + CVV in a row
            Row(
              children: [
                Expanded(
                  child: _FormField(
                    controller: _expiryCtrl,
                    label: 'Expiry',
                    hint: 'MM/YY',
                    prefixIcon: Icons.date_range_rounded,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                      _ExpiryFormatter(),
                    ],
                    maxLength: 5,
                    validator: _validateExpiry,
                    textInputAction: TextInputAction.next,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormFieldObscurable(
                    controller: _cvvCtrl,
                    label: 'CVV',
                    hint: '•••',
                    prefixIcon: Icons.lock_outline_rounded,
                    isObscured: _obscureCvv,
                    onToggleObscure: () =>
                        setState(() => _obscureCvv = !_obscureCvv),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    maxLength: 4,
                    validator: _validateCvv,
                    textInputAction: TextInputAction.next,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Section: Optional ─────────────────────────────────────
            _SectionHeader(title: 'Optional'),
            const SizedBox(height: 12),

            _FormField(
              controller: _labelCtrl,
              label: 'Label',
              hint: 'e.g. Personal Visa, Work Amex',
              prefixIcon: Icons.label_outline_rounded,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
            ),

            const SizedBox(height: 32),

            // ── Save button (bottom) ──────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  disabledBackgroundColor:
                      AppTheme.accentBlue.withOpacity(0.4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        _isEditing ? 'Update Card' : 'Save Card',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Security notice
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined,
                    size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Encrypted with device-level secure storage',
                  style: AppTheme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared form widgets
// ---------------------------------------------------------------------------

/// Reusable dark-themed TextFormField.
class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLength,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.fontFamily,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData prefixIcon;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontFamily: fontFamily,
        fontSize: 15,
        letterSpacing: fontFamily != null ? 1.5 : 0,
      ),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        prefixIcon: prefixIcon,
      ),
    );
  }
}

/// TextFormField variant with an obscure toggle (for CVV).
class _FormFieldObscurable extends StatelessWidget {
  const _FormFieldObscurable({
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    required this.isObscured,
    required this.onToggleObscure,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.maxLength,
    this.validator,
    this.textInputAction,
    this.fontFamily,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData prefixIcon;
  final bool isObscured;
  final VoidCallback onToggleObscure;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: isObscured,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validator: validator,
      textInputAction: textInputAction,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontFamily: fontFamily,
        fontSize: 15,
        letterSpacing: isObscured ? 3.0 : 1.5,
      ),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        prefixIcon: prefixIcon,
      ).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            isObscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          onPressed: onToggleObscure,
          tooltip: isObscured ? 'Show CVV' : 'Hide CVV',
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  required String label,
  required String hint,
  required IconData prefixIcon,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
    hintText: hint,
    hintStyle:
        TextStyle(color: AppTheme.textMuted.withOpacity(0.5), fontSize: 14),
    filled: true,
    fillColor: AppTheme.bgCardElevated,
    prefixIcon: Icon(prefixIcon, color: AppTheme.textSecondary, size: 20),
    prefixIconConstraints:
        const BoxConstraints(minWidth: 48, minHeight: 48),
    counterText: '', // hide the max-length counter
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppTheme.bgCardElevated, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: AppTheme.textMuted.withOpacity(0.2), width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:
          const BorderSide(color: AppTheme.accentBlue, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:
          const BorderSide(color: AppTheme.accentRed, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:
          const BorderSide(color: AppTheme.accentRed, width: 2),
    ),
    errorStyle: const TextStyle(
        color: AppTheme.accentRed, fontSize: 12),
  );
}

// ---------------------------------------------------------------------------
// _SectionHeader
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: AppTheme.textMuted.withOpacity(0.2),
            thickness: 1,
          ),
        ),
      ],
    );
  }
}
