import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../widgets/common.dart';

class NannyDetailScreen extends StatefulWidget {
  const NannyDetailScreen({super.key, required this.nannyId, this.point, this.showChoose = false});

  final int nannyId;
  final LatLng? point;
  final bool showChoose;

  @override
  State<NannyDetailScreen> createState() => _NannyDetailScreenState();
}

class _NannyDetailScreenState extends State<NannyDetailScreen> {
  NannyDetail? _n;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = widget.point;
      final q = p == null ? '' : '?lat=${p.latitude}&lng=${p.longitude}';
      final res = await Api.instance.get('/api/nannies/${widget.nannyId}$q');
      setState(() => _n = NannyDetail.fromJson(Map<String, dynamic>.from(res as Map)));
    } catch (e) {
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    if (n == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load),
      );
    }
    final c = n.card;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                PersonPhoto(photoId: c.photoId, name: c.name, seed: c.id, fontSize: 110),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x661D3557), Colors.transparent, Color(0xCC1D3557)],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.age == null ? c.name : '${c.name}, ${c.age}',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (c.medOk) const VerifiedChip('Медкнижка', dark: true),
                      if (c.policeOk) const VerifiedChip('МВД', dark: true),
                      if (c.isDemo) const VerifiedChip('Демо-анкета', dark: true),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            sliver: SliverList.list(children: [
              Row(children: [
                _Stat(value: c.rating?.toStringAsFixed(1) ?? '—', label: '${c.reviewsCount} отзывов', icon: Icons.star_rounded),
                const SizedBox(width: 10),
                _Stat(value: years(c.experience ?? 0), label: 'опыт', icon: Icons.work_history_rounded),
                const SizedBox(width: 10),
                _Stat(value: '${n.ordersDone}', label: 'заказов', icon: Icons.task_alt_rounded),
              ]),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_rounded, color: kPrimary),
                  title: Text('${money(c.price)} / час', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(c.distanceM == null ? 'Минимальный заказ — 1 час' : '${km(c.distanceM)} от вас · минимум 1 час'),
                ),
              ),
              if ((c.about ?? '').isNotEmpty) ...[
                const SectionTitle('О себе'),
                Text(c.about!, style: const TextStyle(fontSize: 15, height: 1.45)),
              ],
              if ((n.schedule ?? '').isNotEmpty) ...[
                const SectionTitle('Расписание'),
                InfoPlate(icon: Icons.schedule_rounded, child: Text(n.schedule!)),
              ],
              if (n.certificates.isNotEmpty) ...[
                const SectionTitle('Сертификаты'),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: n.certificates.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _showImage(n.certificates[i]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image(
                          image: authImage(n.certificates[i]),
                          width: 140,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 140,
                            color: kWarm.withValues(alpha: 0.2),
                            alignment: Alignment.center,
                            child: const Icon(Icons.description_rounded, color: kPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SectionTitle('Отзывы'),
              if (n.reviews.isEmpty) const Text('Пока нет отзывов', style: TextStyle(color: kMuted)),
              for (final r in n.reviews)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(r.author, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          RatingStars(rating: r.rating.toDouble(), size: 15),
                        ]),
                        if ((r.text ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(r.text!)],
                        const SizedBox(height: 4),
                        Text(dateTime(r.createdAt), style: const TextStyle(color: kMuted, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ),
      bottomSheet: widget.showChoose
          ? Container(
              color: kBg,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              child: FilledButton.icon(
                onPressed: n.available ? () => Navigator.pop(context, true) : null,
                icon: const Icon(Icons.favorite_rounded),
                label: Text(n.available ? 'Выбрать няню' : 'Сейчас недоступна'),
              ),
            )
          : null,
    );
  }

  void _showImage(int id) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(child: Image(image: authImage(id))),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, color: kPrimary, size: 22),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      ),
    );
  }
}
