import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The two Focus screen treatments for Reefish's animated 45.333 × 34 mark.
enum FocusFishMarkVariant { map, sheet }

class FocusFishMark extends StatefulWidget {
  const FocusFishMark({required this.variant, this.animate = true, super.key});

  final FocusFishMarkVariant variant;
  final bool animate;

  @override
  State<FocusFishMark> createState() => _FocusFishMarkState();
}

class _FocusFishMarkState extends State<FocusFishMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  bool _motionRunning = false;

  static const _keyframes = <({double time, Offset value})>[
    (time: 0, value: Offset.zero),
    (time: 10, value: Offset.zero),
    (time: 15, value: Offset(.106, -.181)),
    (time: 20, value: Offset(.44, -.725)),
    (time: 25, value: Offset(.99, -1.375)),
    (time: 30, value: Offset(1.662, -1.746)),
    (time: 32.5, value: Offset(1.993, -1.789)),
    (time: 35, value: Offset(2.291, -1.741)),
    (time: 40, value: Offset(2.739, -1.329)),
    (time: 45, value: Offset(2.957, -.531)),
    (time: 47.5, value: Offset(2.982, -.066)),
    (time: 50, value: Offset(2.962, .371)),
    (time: 55, value: Offset(2.794, .993)),
    (time: 60, value: Offset(2.446, 1.193)),
    (time: 65, value: Offset(1.936, 1.126)),
    (time: 70, value: Offset(1.34, .916)),
    (time: 75, value: Offset(.775, .596)),
    (time: 80, value: Offset(.34, .277)),
    (time: 85, value: Offset(.082, .067)),
    (time: 90, value: Offset.zero),
    (time: 100, value: Offset.zero),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _offset = TweenSequence<Offset>([
      for (var i = 0; i < _keyframes.length - 1; i++)
        TweenSequenceItem<Offset>(
          tween: Tween<Offset>(
            begin: _keyframes[i].value,
            end: _keyframes[i + 1].value,
          ),
          weight: _keyframes[i + 1].time - _keyframes[i].time,
        ),
    ]).animate(_controller);
  }

  void _syncMotion(bool reducedMotion) {
    final shouldRun = widget.animate && !reducedMotion;
    if (_motionRunning == shouldRun) return;
    _motionRunning = shouldRun;
    if (shouldRun) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion(MediaQuery.disableAnimationsOf(context));
  }

  @override
  void didUpdateWidget(covariant FocusFishMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion(MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMap = widget.variant == FocusFishMarkVariant.map;
    return SizedBox(
      width: 45.333,
      height: 34,
      child: ClipRRect(
        borderRadius: isMap ? BorderRadius.circular(20) : BorderRadius.zero,
        child: ColoredBox(
          color: isMap ? const Color(0xFF1E6387) : Colors.transparent,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                _animatedVector(
                  'focus-Vector-6be09cc0-9ab3-4155-84b1-b273f2665a86.svg',
                  left: .1875,
                  top: .1655,
                  right: .1294,
                  bottom: .0623,
                  overflowX: .0504,
                  overflowLeft: .0503,
                  overflowY: .0593,
                  offset: _offset.value,
                ),
                _animatedVector(
                  'focus-Vector1-f227990a-b3f4-4cb8-9c3a-18873145239f.svg',
                  left: .0562,
                  top: .45,
                  right: .8,
                  bottom: .2583,
                  offset: _offset.value,
                ),
                _staticVector(
                  'focus-Vector2-21554272-3e3a-4b48-b809-4793963f60d1.svg',
                  left: .4125,
                  top: .3583,
                  right: .3875,
                  bottom: .2667,
                  overflowX: .1094,
                  overflowLeft: .1094,
                  overflowY: .0778,
                ),
                _animatedVector(
                  'focus-Vector3-bae32dc6-7ed8-4cb3-89d1-f6c5421a8dde.svg',
                  left: .7344,
                  top: .4208,
                  right: .2219,
                  bottom: .5208,
                  offset: _offset.value,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _animatedVector(
    String asset, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    Offset offset = Offset.zero,
    double overflowX = 0,
    double overflowLeft = 0,
    double overflowY = 0,
  }) => Positioned.fill(
    left: left * 45.333,
    top: top * 34,
    right: right * 45.333,
    bottom: bottom * 34,
    child: Transform.translate(
      offset: offset,
      child: _vectorContent(
        asset,
        overflowX: overflowX,
        overflowLeft: overflowLeft,
        overflowY: overflowY,
      ),
    ),
  );

  Widget _staticVector(
    String asset, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    double overflowX = 0,
    double overflowLeft = 0,
    double overflowY = 0,
  }) => Positioned.fill(
    left: left * 45.333,
    top: top * 34,
    right: right * 45.333,
    bottom: bottom * 34,
    child: _vectorContent(
      asset,
      overflowX: overflowX,
      overflowLeft: overflowLeft,
      overflowY: overflowY,
    ),
  );

  Widget _vectorContent(
    String asset, {
    double overflowX = 0,
    double overflowLeft = 0,
    double overflowY = 0,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return OverflowBox(
        alignment: Alignment.center,
        minWidth: width * (1 + overflowLeft + overflowX),
        maxWidth: width * (1 + overflowLeft + overflowX),
        minHeight: height * (1 + 2 * overflowY),
        maxHeight: height * (1 + 2 * overflowY),
        child: Transform.translate(
          offset: Offset(-width * (overflowLeft - overflowX) / 2, 0),
          child: SvgPicture.asset(
            'assets/untracked/$asset',
            width: width * (1 + overflowLeft + overflowX),
            height: height * (1 + 2 * overflowY),
            fit: BoxFit.fill,
          ),
        ),
      );
    },
  );
}
