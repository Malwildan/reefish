import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../map/domain/fishing_point_repository.dart';
import '../../journey/domain/journey_models.dart';
import '../../theme/reef_fish_theme.dart';

/// Form for recording a completed trip. Dates and times are entered in WIB,
/// then converted explicitly to UTC so the result does not depend on device TZ.
class CreateJourneyScreen extends StatefulWidget {
  const CreateJourneyScreen({
    required this.onSubmit,
    this.selection,
    this.pendingTrip,
    this.initialTrip,
    this.source = JourneyTripSource.onboarding,
    this.busy = false,
    this.message,
    this.onBack,
    this.onChooseLocation,
    this.onRetryPending,
    this.onEditPending,
    super.key,
  });

  final ValueChanged<JourneyTripInput> onSubmit;
  final FishingPointSelection? selection;
  final JourneyTripInput? pendingTrip;
  final JourneyTripInput? initialTrip;
  final JourneyTripSource source;
  final bool busy;
  final String? message;
  final VoidCallback? onBack;
  final VoidCallback? onChooseLocation;
  final VoidCallback? onRetryPending;
  final VoidCallback? onEditPending;

  @override
  State<CreateJourneyScreen> createState() => _CreateJourneyScreenState();
}

class _CreateJourneyScreenState extends State<CreateJourneyScreen> {
  static const _wib = Duration(hours: 7);
  late final TextEditingController _fuelController;
  late final TextEditingController _catchController;
  late final TextEditingController _departHourController;
  late final TextEditingController _departMinuteController;
  late final TextEditingController _returnHourController;
  late final TextEditingController _returnMinuteController;
  late DateTime _tripDate;
  String? _validationMessage;

  bool get _readOnly => widget.pendingTrip != null;
  bool get _crossesMidnight {
    final departure = _readTime(_departHourController, _departMinuteController);
    final returned = _readTime(_returnHourController, _returnMinuteController);
    if (departure == null || returned == null) return false;
    return returned.$1 * 60 + returned.$2 < departure.$1 * 60 + departure.$2;
  }

  @override
  void initState() {
    super.initState();
    final nowWib = DateTime.now().toUtc().add(_wib);
    final pending = widget.pendingTrip;
    final seed = pending ?? widget.initialTrip;
    final initialDepart = seed?.departedAt.toUtc().add(_wib) ?? nowWib;
    final initialReturn = seed?.returnedAt.toUtc().add(_wib) ?? nowWib;
    _tripDate = DateTime.utc(
      initialDepart.year,
      initialDepart.month,
      initialDepart.day,
    );
    _fuelController = TextEditingController(
      text: seed?.fuelLiters.toString() ?? '',
    );
    _catchController = TextEditingController(
      text: seed?.catchKg.toString() ?? '',
    );
    _departHourController = TextEditingController(
      text: seed == null ? '' : _two(initialDepart.hour),
    );
    _departMinuteController = TextEditingController(
      text: seed == null ? '00' : _two(initialDepart.minute),
    );
    _returnHourController = TextEditingController(
      text: seed == null ? '' : _two(initialReturn.hour),
    );
    _returnMinuteController = TextEditingController(
      text: seed == null ? '00' : _two(initialReturn.minute),
    );
  }

  @override
  void didUpdateWidget(covariant CreateJourneyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_readOnly) _validationMessage = null;
  }

  @override
  void dispose() {
    _fuelController.dispose();
    _catchController.dispose();
    _departHourController.dispose();
    _departMinuteController.dispose();
    _returnHourController.dispose();
    _returnMinuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 34),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                            key: const ValueKey('journey-back'),
                            onPressed: widget.onBack,
                            padding: EdgeInsets.zero,
                            icon: SvgPicture.asset(
                              'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
                              width: 38,
                              height: 38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SvgPicture.asset(
                          'assets/icons/login-ReefishMarkColorAtoll-fc2ecd40-eb81-448f-a0b0-ab29c7974c23.svg',
                          width: 56,
                          height: 42,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Catat Perjalanan Melaut',
                          style: TextStyle(
                            color: ReefishColors.textPrimary,
                            fontSize: 24,
                            height: 32 / 24,
                            letterSpacing: -0.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'Catat perjalanan melaut yang sudah selesai.',
                          style: TextStyle(
                            color: ReefishColors.textPrimary,
                            fontSize: 14,
                            height: 22 / 14,
                          ),
                        ),
                        const SizedBox(height: 32),
                        IgnorePointer(
                          ignoring: _readOnly || widget.busy,
                          child: Opacity(
                            opacity: _readOnly ? 0.72 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AmountField(
                                  label: 'Bensin yang Dibutuhkan',
                                  controller: _fuelController,
                                  unit: 'Liter',
                                  fieldKey: const ValueKey('journey-fuel'),
                                ),
                                const SizedBox(height: 20),
                                _AmountField(
                                  label: 'Volume Ikan yang Ditangkap',
                                  controller: _catchController,
                                  unit: 'Kg',
                                  fieldKey: const ValueKey('journey-catch'),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _TimeInput(
                                        label: 'Jam Berangkat',
                                        hour: _departHourController,
                                        minute: _departMinuteController,
                                        keyPrefix: 'journey-depart',
                                        onChanged: _onTimeChanged,
                                      ),
                                    ),
                                    const SizedBox(width: 62),
                                    Expanded(
                                      child: _TimeInput(
                                        label: 'Jam Pulang',
                                        hour: _returnHourController,
                                        minute: _returnMinuteController,
                                        keyPrefix: 'journey-return',
                                        onChanged: _onTimeChanged,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                _DateSelector(
                                  date: _tripDate,
                                  onChanged: (date) => setState(() {
                                    _tripDate = DateTime.utc(
                                      date.year,
                                      date.month,
                                      date.day,
                                    );
                                  }),
                                ),
                                if (_crossesMidnight)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Jam pulang lebih awal dari jam berangkat, jadi tanggal pulang mengikuti hari berikutnya.',
                                      style: _bodyStyle(
                                        color: ReefishColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                if (widget.selection == null) ...[
                                  const SizedBox(height: 16),
                                  _ChooseLocation(
                                    onPressed: widget.onChooseLocation,
                                    required: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_readOnly) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Pengiriman perjalanan ini belum terkonfirmasi. Coba kirim lagi dengan data yang sama.',
                            style: _bodyStyle(color: ReefishColors.info),
                          ),
                        ],
                        if (_validationMessage != null ||
                            widget.message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _validationMessage ?? widget.message!,
                            key: const ValueKey('journey-form-message'),
                            style: _bodyStyle(color: const Color(0xFF9A4739)),
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
                    key: const ValueKey('journey-submit'),
                    onPressed: widget.busy
                        ? null
                        : _readOnly
                        ? widget.onEditPending ?? widget.onRetryPending
                        : widget.selection == null
                        ? widget.onChooseLocation
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ReefishColors.primaryAction,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: ReefishColors.primaryAction
                          .withValues(alpha: 0.45),
                      elevation: 2,
                      shadowColor: Colors.black54,
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
                        : Text(
                            _readOnly
                                ? widget.onEditPending == null
                                      ? 'Coba kirim lagi'
                                      : 'Perbaiki data'
                                : 'Lanjutkan',
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final selection = widget.selection;
    if (selection == null) return;
    final fuel = double.tryParse(
      _fuelController.text.trim().replaceAll(',', '.'),
    );
    final catchKg = double.tryParse(
      _catchController.text.trim().replaceAll(',', '.'),
    );
    final departureTime = _readTime(
      _departHourController,
      _departMinuteController,
    );
    final returnTime = _readTime(
      _returnHourController,
      _returnMinuteController,
    );
    if (fuel == null || !fuel.isFinite || fuel <= 0 || fuel > 500) {
      _setError('Masukkan bensin lebih dari 0 dan maksimal 500 liter.');
      return;
    }
    if (catchKg == null || !catchKg.isFinite || catchKg < 0 || catchKg > 5000) {
      _setError('Masukkan hasil tangkapan 0 sampai 5.000 kg.');
      return;
    }
    if (departureTime == null) {
      _setTimeError(
        _departHourController,
        _departMinuteController,
        'berangkat',
      );
      return;
    }
    if (returnTime == null) {
      _setTimeError(_returnHourController, _returnMinuteController, 'pulang');
      return;
    }
    final departedAtWib = DateTime.utc(
      _tripDate.year,
      _tripDate.month,
      _tripDate.day,
      departureTime.$1,
      departureTime.$2,
    );
    var returnedAtWib = DateTime.utc(
      _tripDate.year,
      _tripDate.month,
      _tripDate.day,
      returnTime.$1,
      returnTime.$2,
    );
    if (returnedAtWib.isBefore(departedAtWib)) {
      returnedAtWib = returnedAtWib.add(const Duration(days: 1));
    }
    final departedAt = departedAtWib.subtract(_wib);
    final returnedAt = returnedAtWib.subtract(_wib);
    if (!returnedAt.isAfter(departedAt)) {
      _setError('Jam pulang harus setelah jam berangkat.');
      return;
    }
    final trip = JourneyTripInput(
      source: widget.source,
      departure: JourneyLatLng(
        lat: selection.departure.point.latitude,
        lng: selection.departure.point.longitude,
      ),
      returnPoint: JourneyLatLng(
        lat: selection.departure.point.latitude,
        lng: selection.departure.point.longitude,
      ),
      departedAt: departedAt,
      returnedAt: returnedAt,
      fuelLiters: fuel,
      catchKg: catchKg,
      fishingPoints: [
        JourneyFishingPointInput(
          point: JourneyLatLng(
            lat: selection.point.latitude,
            lng: selection.point.longitude,
          ),
          reportedCatchKg: catchKg,
        ),
      ],
    );
    try {
      trip.validate();
    } on ArgumentError catch (error) {
      _setError(_friendlyError(error));
      return;
    }
    widget.onSubmit(trip);
  }

  void _setError(String message) =>
      setState(() => _validationMessage = message);

  void _setTimeError(
    TextEditingController hour,
    TextEditingController minute,
    String label,
  ) {
    final parsedHour = int.tryParse(hour.text);
    if (hour.text.isEmpty) {
      _setError('Jam $label wajib diisi (00–23).');
      return;
    }
    if (parsedHour == null || parsedHour < 0 || parsedHour > 23) {
      _setError('Masukkan jam $label yang valid (00–23).');
      return;
    }
    if (minute.text.isEmpty) {
      _setError('Menit $label wajib diisi (00–59).');
      return;
    }
    _setError('Masukkan menit $label yang valid (00–59).');
  }

  void _onTimeChanged(String _) => setState(() => _validationMessage = null);

  String _friendlyError(ArgumentError error) {
    final message = error.message?.toString() ?? '';
    if (message.contains('returnedAt cannot')) {
      return 'Waktu pulang masih di masa depan. Periksa tanggal dan jam pulang, atau catat perjalanan setelah selesai.';
    }
    if (message.contains('within 72 hours')) {
      return 'Durasi perjalanan maksimal 72 jam.';
    }
    return 'Periksa kembali waktu perjalanan dan lokasi yang dipilih.';
  }

  static (int, int)? _readTime(
    TextEditingController hour,
    TextEditingController minute,
  ) {
    final h = int.tryParse(hour.text);
    final m = int.tryParse(minute.text);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return (h, m);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.controller,
    required this.unit,
    required this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String unit;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _labelStyle()),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            flex: 238,
            child: _InputBox(
              key: fieldKey,
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              hintText: label,
              textAlign: TextAlign.start,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Expanded(flex: 137, child: _StaticUnitBox(unit: unit)),
        ],
      ),
    ],
  );
}

class _TimeInput extends StatelessWidget {
  const _TimeInput({
    required this.label,
    required this.hour,
    required this.minute,
    required this.keyPrefix,
    required this.onChanged,
  });

  final String label;
  final TextEditingController hour;
  final TextEditingController minute;
  final String keyPrefix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _labelStyle()),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: _InputBox(
              key: ValueKey('$keyPrefix-hour'),
              controller: hour,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: onChanged,
              textAlign: TextAlign.start,
              horizontalPadding: 12,
              hintText: 'JJ',
            ),
          ),
          const SizedBox(width: 4),
          const SizedBox(
            width: 14,
            child: Text(
              ':',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _InputBox(
              key: ValueKey('$keyPrefix-minute'),
              controller: minute,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: onChanged,
              textAlign: TextAlign.start,
              horizontalPadding: 12,
              hintText: 'MM',
            ),
          ),
        ],
      ),
    ],
  );
}

class _StaticUnitBox extends StatelessWidget {
  const _StaticUnitBox({required this.unit});

  final String unit;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: ReefishColors.field,
      border: Border.all(color: ReefishColors.textSecondary, width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      unit,
      style: const TextStyle(color: ReefishColors.textPrimary, fontSize: 14),
    ),
  );
}

class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.hintText,
    this.textAlign = TextAlign.start,
    this.horizontalPadding = 12,
    super.key,
  });

  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final TextAlign textAlign;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 4),
    decoration: BoxDecoration(
      color: ReefishColors.field,
      border: Border.all(color: ReefishColors.border, width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      textAlign: textAlign,
      maxLines: 1,
      style: const TextStyle(
        color: ReefishColors.textPrimary,
        fontSize: 14,
        height: 22 / 14,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: ReefishColors.textSecondary,
          fontSize: 14,
        ),
      ),
    ),
  );
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Tanggal perjalanan', style: _labelStyle()),
      const SizedBox(height: 7),
      OutlinedButton.icon(
        key: const ValueKey('journey-date'),
        onPressed: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            helpText: 'Pilih tanggal berangkat',
            cancelText: 'Batal',
            confirmText: 'Pilih',
          );
          if (selected != null) onChanged(selected);
        },
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text('${_two(date.day)}/${_two(date.month)}/${date.year} (WIB)'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
          foregroundColor: ReefishColors.textPrimary,
          backgroundColor: ReefishColors.field,
          side: const BorderSide(color: ReefishColors.border, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
    ],
  );

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _ChooseLocation extends StatelessWidget {
  const _ChooseLocation({required this.onPressed, required this.required});

  final VoidCallback? onPressed;
  final bool required;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.location_on_outlined),
    label: Text(
      required ? 'Pilih lokasi memancing untuk melanjutkan' : 'Pilih lokasi',
    ),
    style: TextButton.styleFrom(foregroundColor: ReefishColors.info),
  );
}

TextStyle _labelStyle() => const TextStyle(
  color: ReefishColors.textPrimary,
  fontSize: 14,
  height: 20 / 14,
  fontWeight: FontWeight.w600,
);

TextStyle _bodyStyle({required Color color}) =>
    TextStyle(color: color, fontSize: 14, height: 22 / 14);
