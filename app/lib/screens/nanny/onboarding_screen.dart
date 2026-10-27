import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

/// Онбординг и KYC няни: анкета → паспорт → селфи с паспортом → медкнижка и справка МВД.
/// В режиме editMode (после одобрения) редактируются только анкета, фото и сертификаты.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editMode = false});

  final bool editMode;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _exp = TextEditingController();
  final _price = TextEditingController();
  final _about = TextEditingController();
  final _schedule = TextEditingController();
  NannyProfile? _p;
  Object? _error;
  int _step = 0;
  String? _uploading;

  @override
  void initState() {
    super.initState();
    _load(fill: true);
  }

  @override
  void dispose() {
    for (final c in [_name, _age, _exp, _price, _about, _schedule]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool fill = false}) async {
    try {
      final p = NannyProfile.fromJson(Map<String, dynamic>.from(await Api.instance.get('/api/nanny/profile') as Map));
      if (fill) {
        _name.text = p.fullName ?? ref.read(sessionProvider).value?.name ?? '';
        _age.text = p.age?.toString() ?? '';
        _exp.text = p.experience?.toString() ?? '';
        _price.text = p.price?.toString() ?? '';
        _about.text = p.about ?? '';
        _schedule.text = p.schedule ?? '';
      }
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _saveProfile() async {
    if (!_form.currentState!.validate()) throw ApiException(400, 'Проверьте поля анкеты');
    final res = await Api.instance.put('/api/nanny/profile', {
      'full_name': _name.text.trim(),
      'age': int.tryParse(_age.text),
      'experience': int.tryParse(_exp.text),
      'price': int.tryParse(_price.text.replaceAll(' ', '')),
      'about': _about.text.trim(),
      'schedule': _schedule.text.trim(),
    });
    setState(() => _p = NannyProfile.fromJson(Map<String, dynamic>.from(res as Map)));
  }

  Future<void> _upload(String kind, ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1800,
      imageQuality: 82,
      preferredCameraDevice: kind == 'selfie' || kind == 'photo' ? CameraDevice.front : CameraDevice.rear,
    );
    if (file == null) return;
    setState(() => _uploading = kind);
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final type = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      await Api.instance.upload('/api/files/$kind', bytes, type);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _removeCert(int id) async {
    try {
      await Api.instance.delete('/api/files/$id');
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _submit() async {
    await Api.instance.post('/api/nanny/submit');
    await ref.read(sessionProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load),
      );
    }
    if (widget.editMode) return _editScaffold(p);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Анкета няни'),
        actions: [TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Выйти'))],
      ),
      body: Form(
        key: _form,
        child: Stepper(
          currentStep: _step,
          onStepTapped: (i) => setState(() => _step = i),
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(children: [
              Expanded(
                child: _step == 3
                    ? BusyButton(label: 'Отправить на проверку', icon: Icons.verified_user_rounded, onPressed: _canSubmit(p) ? _submit : null)
                    : BusyButton(
                        label: 'Далее',
                        onPressed: () async {
                          if (_step == 0) await _saveProfile();
                          setState(() => _step++);
                        },
                      ),
              ),
              if (_step > 0) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _step--), child: const Text('Назад')),
              ],
            ]),
          ),
          steps: [
            Step(
              title: const Text('Анкета'),
              subtitle: const Text('ФИО, возраст, опыт, о себе'),
              isActive: _step >= 0,
              state: _profileFilled(p) ? StepState.complete : StepState.indexed,
              content: Column(children: [
                if (p.status == 'rejected') ...[
                  InfoPlate(
                    icon: Icons.error_outline_rounded,
                    color: kPink,
                    child: Text('Анкета отклонена: ${p.rejectReason ?? ''}\nИсправьте данные и отправьте повторно.'),
                  ),
                  const SizedBox(height: 12),
                ],
                ..._profileFields(p),
              ]),
            ),
            Step(
              title: const Text('Паспорт'),
              subtitle: const Text('Фото разворота с фотографией'),
              isActive: _step >= 1,
              state: p.doc('passport') != null ? StepState.complete : StepState.indexed,
              content: _DocTile(
                title: 'Паспорт',
                hint: 'Сфотографируйте разворот с фото при хорошем освещении: все поля и машиночитаемая зона (две строки внизу) должны быть читаемы.',
                doc: p.doc('passport'),
                busy: _uploading == 'passport',
                onPick: (s) => _upload('passport', s),
              ),
            ),
            Step(
              title: const Text('Селфи с паспортом'),
              subtitle: const Text('Подтверждение личности'),
              isActive: _step >= 2,
              state: p.doc('selfie') != null ? StepState.complete : StepState.indexed,
              content: _DocTile(
                title: 'Селфи с паспортом',
                hint: 'Держите открытый паспорт рядом с лицом. Лицо и фото в паспорте должны быть хорошо видны.',
                doc: p.doc('selfie'),
                busy: _uploading == 'selfie',
                onPick: (s) => _upload('selfie', s),
              ),
            ),
            Step(
              title: const Text('Медкнижка и справка МВД'),
              subtitle: const Text('Проверка модератором'),
              isActive: _step >= 3,
              state: p.doc('medbook') != null && p.doc('police') != null ? StepState.complete : StepState.indexed,
              content: Column(children: [
                _DocTile(
                  title: 'Медицинская книжка',
                  hint: 'Страница с отметками о действующих осмотрах.',
                  doc: p.doc('medbook'),
                  busy: _uploading == 'medbook',
                  onPick: (s) => _upload('medbook', s),
                ),
                const SizedBox(height: 12),
                _DocTile(
                  title: 'Справка об отсутствии судимости',
                  hint: 'Получить справку можно на my.gov.uz. Загрузите фото или скриншот справки.',
                  doc: p.doc('police'),
                  busy: _uploading == 'police',
                  onPick: (s) => _upload('police', s),
                ),
                const SizedBox(height: 12),
                _certificates(p),
                if (!_canSubmit(p)) ...[
                  const SizedBox(height: 12),
                  const InfoPlate(child: Text('Чтобы отправить анкету, заполните профиль, добавьте фото и все документы.')),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  bool _profileFilled(NannyProfile p) => (p.fullName ?? '').isNotEmpty && p.age != null && p.experience != null && p.price != null;

  bool _canSubmit(NannyProfile p) =>
      _profileFilled(p) && ['photo', 'passport', 'selfie', 'medbook', 'police'].every((k) => p.doc(k) != null);

  Widget _editScaffold(NannyProfile p) {
    return Scaffold(
      appBar: AppBar(title: const Text('Моя анкета')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            ..._profileFields(p),
            const SizedBox(height: 16),
            _certificates(p),
            const SizedBox(height: 20),
            BusyButton(
              label: 'Сохранить',
              onPressed: () async {
                await _saveProfile();
                if (mounted) showMessage(context, 'Анкета сохранена');
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _profileFields(NannyProfile p) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null;
    final photo = p.doc('photo');
    return [
      Center(
        child: GestureDetector(
          onTap: () => _pickSource('photo'),
          child: Stack(children: [
            SizedBox(
              width: 112,
              height: 112,
              child: _uploading == 'photo'
                  ? const CircularProgressIndicator()
                  : PersonPhoto(photoId: photo?.id, name: _name.text, radius: 56, fontSize: 36),
            ),
            const Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(radius: 18, backgroundColor: kPink, child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Center(child: Text(photo == null ? 'Добавьте фото профиля — его увидят родители' : 'Фото профиля', style: const TextStyle(color: kMuted))),
      const SizedBox(height: 16),
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'ФИО полностью'),
        validator: (v) => (v ?? '').trim().length < 5 ? 'Укажите ФИО полностью' : null,
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextFormField(
            controller: _age,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Возраст'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 18 || n > 75 ? 'От 18 до 75' : null;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _exp,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Опыт, лет'),
            validator: required,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      TextFormField(
        controller: _price,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Стоимость часа, сум', hintText: 'Например, 60000'),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return n == null || n < 10000 || n > 1000000 ? 'От 10 000 до 1 000 000 сум' : null;
        },
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: _about,
        maxLines: 4,
        minLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(labelText: 'О себе', hintText: 'Образование, опыт, чем любите заниматься с детьми'),
      ),
      TextFormField(
        controller: _schedule,
        decoration: const InputDecoration(labelText: 'Расписание', hintText: 'Пн–Пт 9:00–19:00'),
      ),
    ];
  }

  Widget _certificates(NannyProfile p) {
    final certs = p.docs.where((d) => d.kind == 'cert').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Сертификаты и дипломы (по желанию)', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in certs)
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(image: authImage(c.id), width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 84, height: 84)),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                onTap: () => _removeCert(c.id),
                child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
              ),
            ),
          ]),
        InkWell(
          onTap: _uploading == 'cert' ? null : () => _upload('cert', ImageSource.gallery),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: _uploading == 'cert'
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.add_photo_alternate_outlined, color: kPrimary),
          ),
        ),
      ]),
    ]);
  }

  Future<void> _pickSource(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Камера'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Галерея'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source != null) await _upload(kind, source);
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.title, required this.hint, required this.doc, required this.busy, required this.onPick});

  final String title;
  final String hint;
  final Doc? doc;
  final bool busy;
  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(doc == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, color: doc == null ? kMuted : kOk),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 10),
          if (busy)
            const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
          else if (doc != null && doc!.mime.startsWith('image/'))
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(image: authImage(doc!.id), height: 160, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(height: 40)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => onPick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(doc == null ? 'Камера' : 'Заново'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => onPick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Галерея'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
