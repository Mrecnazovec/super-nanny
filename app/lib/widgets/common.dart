import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';

void showMessage(BuildContext context, Object error) {
  final text = error is ApiException ? error.message : error.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

ImageProvider authImage(int fileId) => NetworkImage(Api.instance.fileUrl(fileId), headers: Api.instance.authHeaders);

/// Логотип: синий скруглённый квадрат, розовое сердце и тёплое «солнце».
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kPrimary,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: size * 0.3, offset: Offset(0, size * 0.1))],
      ),
      child: Stack(
        children: [
          Center(child: Icon(Icons.favorite_rounded, color: kPink, size: size * 0.6)),
          Positioned(
            right: size * 0.14,
            top: size * 0.12,
            child: Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: const BoxDecoration(color: kWarm, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

const _avatarGradients = [
  [Color(0xFF1D3557), Color(0xFF457B9D)],
  [Color(0xFFE63946), Color(0xFFF4A261)],
  [Color(0xFF2A9D8F), Color(0xFF8AB17D)],
  [Color(0xFF6D597A), Color(0xFFB56576)],
  [Color(0xFFF4A261), Color(0xFFE9C46A)],
];

String initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Фото из защищённого хранилища или градиент с инициалами.
class PersonPhoto extends StatelessWidget {
  const PersonPhoto({super.key, this.photoId, this.name, this.seed = 0, this.radius = 0, this.fontSize = 18});

  final int? photoId;
  final String? name;
  final int seed;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = _avatarGradients[seed.abs() % _avatarGradients.length];
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w800),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: photoId == null
          ? placeholder
          : Image(
              image: authImage(photoId!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
            ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.photoId, this.name, this.seed = 0, this.size = 48});

  final int? photoId;
  final String? name;
  final int seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: PersonPhoto(photoId: photoId, name: name, seed: seed, radius: size / 2, fontSize: size * 0.36),
    );
  }
}

/// Значок верификации: щит с галочкой.
class VerifiedChip extends StatelessWidget {
  const VerifiedChip(this.label, {super.key, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.18) : kOk.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, size: 15, color: dark ? Colors.white : kOk),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? Colors.white : kOk)),
        ],
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 16, this.color = kWarm});

  final double rating;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 0.75 ? Icons.star_rounded : (v >= 0.25 ? Icons.star_half_rounded : Icons.star_outline_rounded);
        return Icon(icon, size: size, color: color);
      }),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'completed' => (kOk.withValues(alpha: 0.12), kOk),
      'cancelled' || 'declined' || 'expired' => (kPink.withValues(alpha: 0.1), kPink),
      'pending' => (kWarm.withValues(alpha: 0.25), const Color(0xFF9A4F12)),
      _ => (kPrimary.withValues(alpha: 0.08), kPrimary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(orderStatusLabels[status] ?? status, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Тёплая жёлтая плашка с подсказкой.
class InfoPlate extends StatelessWidget {
  const InfoPlate({super.key, required this.child, this.icon = Icons.info_outline_rounded, this.color = kWarm});

  final Widget child;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color == kWarm ? const Color(0xFF9A4F12) : color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: DefaultTextStyle.merge(style: const TextStyle(color: kPrimary, height: 1.35), child: child)),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: kMuted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(width: 200, child: FilledButton(onPressed: onRetry, child: const Text('Повторить'))),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, size: 44, color: kPrimary),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Кнопка, которая сама показывает индикатор, пока выполняется действие.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.color, this.icon, this.outlined = false});

  final String label;
  final Future<void> Function()? onPressed;
  final Color? color;
  final IconData? icon;
  final bool outlined;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ],
          );
    if (widget.outlined) return OutlinedButton(onPressed: onPressed, child: child);
    return FilledButton(
      onPressed: onPressed,
      style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kPrimary)),
    );
  }
}
