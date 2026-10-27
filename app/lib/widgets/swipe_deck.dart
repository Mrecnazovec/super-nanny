import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models.dart';
import 'common.dart';

enum SwipeDirection { left, right }

/// Стопка карточек нянь в стиле Tinder.
/// Вправо — «ВЫБРАТЬ» (зелёный штамп), влево — «ПРОПУСТИТЬ» (красный штамп).
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.items,
    required this.onSwiped,
    required this.onTap,
    required this.empty,
    this.onIndexChanged,
  });

  final List<NannyCard> items;
  final void Function(NannyCard item, SwipeDirection direction) onSwiped;
  final void Function(NannyCard item) onTap;
  final ValueChanged<int>? onIndexChanged;
  final Widget empty;

  @override
  State<SwipeDeck> createState() => SwipeDeckState();
}

class SwipeDeckState extends State<SwipeDeck> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Animation<Offset>? _flight;
  Offset _drag = Offset.zero;
  int _index = 0;
  SwipeDirection? _pending;
  Size _size = Size.zero;

  NannyCard? get current => _index < widget.items.length ? widget.items[_index] : null;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_flight != null) setState(() => _drag = _flight!.value);
    });
    _anim.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      final dir = _pending;
      if (dir != null && current != null) {
        final item = current!;
        setState(() {
          _index++;
          _drag = Offset.zero;
          _pending = null;
        });
        widget.onIndexChanged?.call(_index);
        widget.onSwiped(item, dir);
      }
      _flight = null;
    });
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _index = 0;
      _drag = Offset.zero;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Программный свайп — для кнопок под карточкой.
  void swipe(SwipeDirection dir) {
    if (current == null || _anim.isAnimating) return;
    _flyOut(dir);
  }

  void _flyOut(SwipeDirection dir) {
    HapticFeedback.lightImpact();
    _pending = dir;
    final w = _size.width == 0 ? 400.0 : _size.width;
    final target = Offset(dir == SwipeDirection.right ? w * 1.6 : -w * 1.6, _drag.dy + 40);
    _flight = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  void _springBack() {
    _pending = null;
    _flight = Tween(begin: _drag, end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim.forward(from: 0);
  }

  void _onPanEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    final threshold = _size.width * 0.28;
    if (_drag.dx > threshold || vx > 900) {
      _flyOut(SwipeDirection.right);
    } else if (_drag.dx < -threshold || vx < -900) {
      _flyOut(SwipeDirection.left);
    } else {
      _springBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (current == null) return widget.empty;
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      final progress = (_drag.dx / (_size.width * 0.4)).clamp(-1.0, 1.0);
      final cards = <Widget>[];
      // Две карточки «под» верхней — для ощущения стопки.
      for (var depth = 2; depth >= 1; depth--) {
        final i = _index + depth;
        if (i >= widget.items.length) continue;
        final lift = depth == 1 ? progress.abs() : 0.0;
        final scale = 1 - 0.05 * depth + 0.05 * lift;
        cards.add(Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, (14.0 * depth) - 14 * lift),
            child: Transform.scale(scale: scale, child: NannySwipeCard(item: widget.items[i])),
          ),
        ));
      }
      cards.add(Positioned.fill(
        child: GestureDetector(
          onTap: () => widget.onTap(current!),
          onPanStart: (_) => _anim.stop(),
          onPanUpdate: (d) => setState(() => _drag += d.delta),
          onPanEnd: _onPanEnd,
          child: Transform.translate(
            offset: _drag,
            child: Transform.rotate(
              angle: progress * math.pi / 14,
              child: NannySwipeCard(item: current!, stamp: progress),
            ),
          ),
        ),
      ));
      return Stack(clipBehavior: Clip.none, children: cards);
    });
  }
}

class NannySwipeCard extends StatelessWidget {
  const NannySwipeCard({super.key, required this.item, this.stamp = 0});

  final NannyCard item;

  /// -1..1: насколько проявлен штамп «ПРОПУСТИТЬ» / «ВЫБРАТЬ».
  final double stamp;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PersonPhoto(photoId: item.photoId, name: item.name, seed: item.id, fontSize: 96),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.transparent, Color(0xE61D3557)],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              if (item.isDemo)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)),
                    child: const Text('ДЕМО', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ),
              if (item.distanceM != null)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.near_me_rounded, size: 14, color: kPrimary),
                      const SizedBox(width: 4),
                      Text(km(item.distanceM), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kPrimary)),
                    ]),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.age == null ? item.name : '${item.name}, ${item.age}',
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (item.rating != null) ...[
                        RatingStars(rating: item.rating!, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${item.rating!.toStringAsFixed(1)} · ${item.reviewsCount} отз.',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ] else
                        const Text('Новая няня', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _Fact(icon: Icons.work_history_rounded, text: 'Опыт ${years(item.experience ?? 0)}'),
                      const SizedBox(width: 8),
                      _Fact(icon: Icons.payments_rounded, text: '${money(item.price)}/ч'),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (item.medOk) const VerifiedChip('Медкнижка', dark: true),
                      if (item.policeOk) const VerifiedChip('МВД', dark: true),
                    ]),
                  ],
                ),
              ),
              if (stamp > 0.05)
                Positioned(top: 48, left: 24, child: _Stamp(text: 'ВЫБРАТЬ', color: kOk, angle: -0.35, opacity: stamp)),
              if (stamp < -0.05)
                Positioned(top: 48, right: 24, child: _Stamp(text: 'ПРОПУСТИТЬ', color: kPink, angle: 0.35, opacity: -stamp)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: kPrimary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color, required this.angle, required this.opacity});

  final String text;
  final Color color;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0) * 0.9,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ),
      ),
    );
  }
}
