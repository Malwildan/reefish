import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../journey/domain/journey_models.dart';
import '../../theme/reef_fish_theme.dart';

/// Collects the boat attributes required by the journey API.
class BoatSetupScreen extends StatefulWidget {
  const BoatSetupScreen({
    required this.onSubmit,
    this.homePort,
    this.busy = false,
    this.message,
    this.onBack,
    this.onChooseLocation,
    super.key,
  });

  final ValueChanged<JourneyBoatInput> onSubmit;
  final JourneyLatLng? homePort;
  final bool busy;
  final String? message;
  final VoidCallback? onBack;
  final VoidCallback? onChooseLocation;

  @override
  State<BoatSetupScreen> createState() => _BoatSetupScreenState();
}

class _BoatSetupScreenState extends State<BoatSetupScreen> {
  final _nameController = TextEditingController();
  final _engineController = TextEditingController();
  final _lengthController = TextEditingController();
  String _fuelType = 'solar';
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _engineController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      minimum: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 21, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 382),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: IconButton(
                          onPressed: widget.onBack,
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back,
                            color: ReefishColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Informasi Kapal',
                        style: TextStyle(
                          color: ReefishColors.textPrimary,
                          fontSize: 24,
                          height: 32 / 24,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Lengkapi data kapal untuk mencatat perjalananmu.',
                        style: TextStyle(
                          color: ReefishColors.textPrimary,
                          fontSize: 14,
                          height: 22 / 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _BoatTextField(
                        label: 'Nama kapal (opsional)',
                        controller: _nameController,
                        hint: 'Nama kapal',
                        maxLength: 60,
                        formatters: [LengthLimitingTextInputFormatter(60)],
                      ),
                      const SizedBox(height: 20),
                      _BoatTextField(
                        label: 'Kekuatan mesin',
                        controller: _engineController,
                        hint: 'Contoh: 15',
                        unit: 'HP',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _BoatTextField(
                        label: 'Panjang kapal',
                        controller: _lengthController,
                        hint: 'Contoh: 8',
                        unit: 'meter',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Jenis bahan bakar', style: _boatLabel),
                      const SizedBox(height: 7),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: _fieldDecoration,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const ValueKey('boat-fuel-type'),
                            value: _fuelType,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'solar',
                                child: Text('Solar'),
                              ),
                              DropdownMenuItem(
                                value: 'bensin',
                                child: Text('Bensin'),
                              ),
                            ],
                            onChanged: widget.busy
                                ? null
                                : (value) => setState(() => _fuelType = value!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Pelabuhan asal', style: _boatLabel),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: _fieldDecoration,
                        child: widget.homePort == null
                            ? TextButton.icon(
                                onPressed: widget.onChooseLocation,
                                icon: const Icon(Icons.location_on_outlined),
                                label: const Text(
                                  'Pilih lokasi pelabuhan di peta',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: ReefishColors.info,
                                ),
                              )
                            : Text(
                                '${widget.homePort!.lat.toStringAsFixed(5)}, ${widget.homePort!.lng.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 22 / 14,
                                ),
                              ),
                      ),
                      if (_error != null || widget.message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error ?? widget.message!,
                          key: const ValueKey('boat-form-message'),
                          style: const TextStyle(
                            color: ReefishColors.signupAccent,
                            fontSize: 14,
                            height: 22 / 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 382),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('boat-submit'),
                  onPressed: widget.busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ReefishColors.primaryAction,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(
                      side: BorderSide(color: ReefishColors.brand, width: 2),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      height: 24 / 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: widget.busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Lanjutkan'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _submit() {
    final engineHp = double.tryParse(
      _engineController.text.trim().replaceAll(',', '.'),
    );
    final lengthM = double.tryParse(
      _lengthController.text.trim().replaceAll(',', '.'),
    );
    if (engineHp == null ||
        !engineHp.isFinite ||
        engineHp < 1 ||
        engineHp > 500) {
      setState(() => _error = 'Kekuatan mesin harus antara 1 dan 500 HP.');
      return;
    }
    if (lengthM == null || !lengthM.isFinite || lengthM < 2 || lengthM > 30) {
      setState(() => _error = 'Panjang kapal harus antara 2 dan 30 meter.');
      return;
    }
    final homePort = widget.homePort;
    if (homePort == null) {
      setState(() => _error = 'Pilih lokasi pelabuhan asal di peta.');
      return;
    }
    final name = _nameController.text.trim();
    final input = JourneyBoatInput(
      name: name.isEmpty ? null : name,
      engineHp: engineHp,
      boatLengthM: lengthM,
      fuelType: _fuelType,
      homePort: homePort,
    );
    try {
      input.validate();
    } on ArgumentError {
      setState(
        () => _error = 'Periksa kembali data kapal dan lokasi pelabuhan.',
      );
      return;
    }
    widget.onSubmit(input);
  }
}

class _BoatTextField extends StatelessWidget {
  const _BoatTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.unit,
    this.keyboardType,
    this.formatters,
    this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? unit;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _boatLabel),
      const SizedBox(height: 7),
      Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _fieldDecoration,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: formatters,
                maxLength: maxLength,
                style: const TextStyle(
                  color: ReefishColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: ReefishColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (unit != null)
              Text(
                unit!,
                style: const TextStyle(
                  color: ReefishColors.textSecondary,
                  fontSize: 14,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

const _boatLabel = TextStyle(
  color: ReefishColors.textPrimary,
  fontSize: 14,
  height: 20 / 14,
  fontWeight: FontWeight.w600,
);

const _fieldDecoration = BoxDecoration(
  color: ReefishColors.field,
  border: Border.fromBorderSide(
    BorderSide(color: ReefishColors.border, width: 2),
  ),
  borderRadius: BorderRadius.all(Radius.circular(12)),
);
