import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _VerificationRequestException implements Exception {
  const _VerificationRequestException(this.code);
  final String code;
}

class VerificationRequestScreen extends StatefulWidget {
  const VerificationRequestScreen({super.key});
  @override
  State<VerificationRequestScreen> createState() => _VerificationRequestScreenState();
}

class _VerificationRequestScreenState extends State<VerificationRequestScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _registration = TextEditingController();
  final _nationalId = TextEditingController();
  final _links = TextEditingController();
  final _explanation = TextEditingController();
  final _picker = ImagePicker();
  String _type = 'individual';
  String _category = 'سایر';
  int _step = 0;
  bool _busy = false;
  final List<XFile> _evidence = [];
  Map<String, String> get _categoryLabels => {
    'خبرگزاری و رسانه': _t.verificationCategoryMedia,
    'روزنامه‌نگار': _t.verificationCategoryJournalist,
    'خبرنگار': _t.verificationCategoryReporter,
    'گزارشگر ورزشی': _t.verificationCategorySportsReporter,
    'مجری': _t.verificationCategoryPresenter,
    'بازیگر': _t.verificationCategoryActor,
    'کارگردان': _t.verificationCategoryDirector,
    'خواننده و موسیقی‌دان': _t.verificationCategoryMusician,
    'نویسنده و مترجم': _t.verificationCategoryWriter,
    'هنرمند و عکاس': _t.verificationCategoryArtist,
    'ورزشکار': _t.verificationCategoryAthlete,
    'مربی ورزشی': _t.verificationCategoryCoach,
    'سیاستمدار': _t.verificationCategoryPolitician,
    'دیپلمات': _t.verificationCategoryDiplomat,
    'پژوهشگر و استاد دانشگاه': _t.verificationCategoryAcademic,
    'پزشک و متخصص سلامت': _t.verificationCategoryHealthProfessional,
    'وکیل و حقوق‌دان': _t.verificationCategoryLegal,
    'کارآفرین': _t.verificationCategoryEntrepreneur,
    'مدیر کسب‌وکار': _t.verificationCategoryBusinessManager,
    'فناوری و استارتاپ': _t.verificationCategoryTechnology,
    'آموزش و مدرس': _t.verificationCategoryEducation,
    'فعال اجتماعی': _t.verificationCategoryActivist,
    'فروشگاه و خرده‌فروشی': _t.verificationCategoryRetail,
    'رستوران و کافه': _t.verificationCategoryRestaurant,
    'پزشکی و درمانگاه': _t.verificationCategoryClinic,
    'خدمات فنی و مکانیکی': _t.verificationCategoryTechnical,
    'ساخت‌وساز و املاک': _t.verificationCategoryConstruction,
    'حمل‌ونقل': _t.verificationCategoryTransport,
    'گردشگری و هتلداری': _t.verificationCategoryTourism,
    'سازمان مردم‌نهاد': _t.verificationCategoryNgo,
    'شرکت و مؤسسه': _t.verificationCategoryCompany,
    'سایر': _t.verificationCategoryOther,
  };

  static const _categories = [
    'خبرگزاری و رسانه','روزنامه‌نگار','خبرنگار','گزارشگر ورزشی','مجری','بازیگر','کارگردان',
    'خواننده و موسیقی‌دان','نویسنده و مترجم','هنرمند و عکاس','ورزشکار','مربی ورزشی',
    'سیاستمدار','دیپلمات','پژوهشگر و استاد دانشگاه','پزشک و متخصص سلامت','وکیل و حقوق‌دان',
    'کارآفرین','مدیر کسب‌وکار','فناوری و استارتاپ','آموزش و مدرس','فعال اجتماعی',
    'فروشگاه و خرده‌فروشی','رستوران و کافه','پزشکی و درمانگاه','خدمات فنی و مکانیکی',
    'ساخت‌وساز و املاک','حمل‌ونقل','گردشگری و هتلداری','سازمان مردم‌نهاد','شرکت و مؤسسه','سایر'
  ];

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _registration.dispose(); _nationalId.dispose();
    _links.dispose(); _explanation.dispose(); super.dispose();
  }

  Future<void> _pickEvidence() async {
    if (_evidence.length >= 5) return;
    final files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1800);
    if (!mounted || files.isEmpty) return;
    setState(() => _evidence.addAll(files.take(5 - _evidence.length)));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final client = Supabase.instance.client;
      final paths = <String>[];
      for (var i = 0; i < _evidence.length; i++) {
        final file = _evidence[i];
        final bytes = await file.readAsBytes();
        if (bytes.length > 10 * 1024 * 1024) throw const _VerificationRequestException('file_size');
        final ext = file.name.split('.').last.toLowerCase();
        if (!const ['jpg','jpeg','png','webp'].contains(ext)) throw const _VerificationRequestException('file_format');
        final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}_$i.$ext';
        await client.storage.from('verification-evidence').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg'));
        paths.add(path);
      }
      final publicLinks = _links.text.split(RegExp(r'[\n,;]+')).map((s) => s.trim()).where((s) => s.startsWith('https://') || s.startsWith('http://')).take(10).toList();
      await client.from('verification_requests').insert({
        'user_id': user.id, 'applicant_type': _type, 'category': _category,
        'legal_name': _name.text.trim(), 'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        if (_type == 'organization') 'organization_registration_number': _registration.text.trim(),
        if (_type == 'organization') 'organization_national_id': _nationalId.text.trim(),
        'public_links': publicLinks, 'explanation': _explanation.text.trim(), 'evidence_paths': paths,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t.verificationSubmitted)));
      Navigator.pop(context);
    } catch (e) {
      final message = e is _VerificationRequestException
          ? (e.code == 'file_size' ? _t.verificationFileTooLarge : _t.verificationFileFormatInvalid)
          : _t.verificationSubmitFailed;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t.verificationRequestTitle)),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(18), children: [
      LinearProgressIndicator(value: (_step + 1) / 3),
      const SizedBox(height: 12),
      Text(_t.verificationStep(_step + 1, 3), style: Theme.of(context).textTheme.labelLarge),
      if (_step == 0) ...[
        Text(_t.verificationAccountType, style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(segments: const [
          ButtonSegment(value: 'individual', label: Text(_t.verificationIndividual), icon: Icon(Icons.person_outline)),
          ButtonSegment(value: 'organization', label: Text(_t.verificationOrganization), icon: Icon(Icons.business_outlined)),
        ], selected: {_type}, onSelectionChanged: (s) => setState(() => _type = s.first)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(value: _category, isExpanded: true,
          decoration: InputDecoration(labelText: _t.verificationCategory),
          items: _categories.map((v) => DropdownMenuItem(value: v, child: Text(_categoryLabels[v] ?? v))).toList(),
          onChanged: (v) => setState(() => _category = v ?? 'سایر')),
        const SizedBox(height: 14),
        TextFormField(controller: _name, decoration: InputDecoration(labelText: _type == 'individual' ? _t.verificationFullName : _t.verificationOrganizationName),
          validator: (v) => (v?.trim().length ?? 0) < 3 ? _t.verificationRequired : null),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: _t.verificationPhoneOptional)),
        if (_type == 'organization') ...[
          TextFormField(controller: _registration, decoration: InputDecoration(labelText: _t.verificationRegistrationNumber)),
          TextFormField(controller: _nationalId, decoration: InputDecoration(labelText: _t.verificationNationalId)),
        ],
      ],
      if (_step == 1) ...[
        TextFormField(controller: _links, minLines: 3, maxLines: 5, decoration: InputDecoration(labelText: _t.verificationPublicLinks, hintText: _t.verificationLinksHint)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pickEvidence, icon: const Icon(Icons.attach_file), label: Text(_t.verificationAddEvidence(_evidence.length, 5))),
        Text(_t.verificationEvidenceInstructions, style: TextStyle(fontSize: 12)),
        for (final file in _evidence) ListTile(dense: true, leading: const Icon(Icons.image_outlined), title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _evidence.remove(file)))),
      ],
      if (_step == 2) ...[
        TextFormField(controller: _explanation, minLines: 5, maxLines: 9, maxLength: 4000,
          decoration: InputDecoration(labelText: _t.verificationExplanation),
          validator: (v) => (v?.trim().length ?? 0) < 20 ? _t.verificationExplanationRequired : null),
        Text(_t.verificationDisclaimer, style: TextStyle(fontSize: 12)),
      ],
      const SizedBox(height: 22),
      Row(children: [
        if (_step > 0) Expanded(child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: Text(_t.verificationPrevious))),
        if (_step > 0) const SizedBox(width: 10),
        Expanded(child: FilledButton(
          onPressed: _busy ? null : () {
            if (_step < 2) {
              if (_step == 0 && !(_form.currentState?.validate() ?? false)) return;
              setState(() => _step++);
            } else { _submit(); }
          },
          child: _busy ? const SizedBox(height: 18,width: 18,child: CircularProgressIndicator(strokeWidth: 2)) : Text(_step == 2 ? _t.verificationSubmitForReview : _t.verificationContinue),
        )),
      ]),
    ])),
  );
}
