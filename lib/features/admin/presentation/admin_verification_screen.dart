import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/admin_service.dart';

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});
  @override
  State<AdminVerificationScreen> createState() => _AdminVerificationScreenState();
}
class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  String _statusLabel(String status) => switch (status) {
    'pending' => _t.adminVerificationPending,
    'under_review' => _t.adminVerificationUnderReview,
    'needs_info' => _t.adminVerificationNeedsInfo,
    'approved' => _t.adminVerificationApproved,
    'rejected' => _t.adminVerificationRejected,
    _ => status,
  };
  String _categoryLabel(String? category) {
    const categoryKeys = <String, String>{
      'خبرگزاری و رسانه':'verificationCategoryMedia','روزنامه‌نگار':'verificationCategoryJournalist',
      'خبرنگار':'verificationCategoryReporter','گزارشگر ورزشی':'verificationCategorySportsReporter',
      'مجری':'verificationCategoryPresenter','بازیگر':'verificationCategoryActor','کارگردان':'verificationCategoryDirector',
      'خواننده و موسیقی‌دان':'verificationCategoryMusician','نویسنده و مترجم':'verificationCategoryWriter',
      'هنرمند و عکاس':'verificationCategoryArtist','ورزشکار':'verificationCategoryAthlete','مربی ورزشی':'verificationCategoryCoach',
      'سیاستمدار':'verificationCategoryPolitician','دیپلمات':'verificationCategoryDiplomat',
      'پژوهشگر و استاد دانشگاه':'verificationCategoryAcademic','پزشک و متخصص سلامت':'verificationCategoryHealthProfessional',
      'وکیل و حقوق‌دان':'verificationCategoryLegal','کارآفرین':'verificationCategoryEntrepreneur',
      'مدیر کسب‌وکار':'verificationCategoryBusinessManager','فناوری و استارتاپ':'verificationCategoryTechnology',
      'آموزش و مدرس':'verificationCategoryEducation','فعال اجتماعی':'verificationCategoryActivist',
      'فروشگاه و خرده‌فروشی':'verificationCategoryRetail','رستوران و کافه':'verificationCategoryRestaurant',
      'پزشکی و درمانگاه':'verificationCategoryClinic','خدمات فنی و مکانیکی':'verificationCategoryTechnical',
      'ساخت‌وساز و املاک':'verificationCategoryConstruction','حمل‌ونقل':'verificationCategoryTransport',
      'گردشگری و هتلداری':'verificationCategoryTourism','سازمان مردم‌نهاد':'verificationCategoryNgo',
      'شرکت و مؤسسه':'verificationCategoryCompany','سایر':'verificationCategoryOther',
    };
    final key = categoryKeys[category];
    if (key == null) return category ?? '—';
    return switch (key) {
      'verificationCategoryMedia' => _t.verificationCategoryMedia,
      'verificationCategoryJournalist' => _t.verificationCategoryJournalist,
      'verificationCategoryReporter' => _t.verificationCategoryReporter,
      'verificationCategorySportsReporter' => _t.verificationCategorySportsReporter,
      'verificationCategoryPresenter' => _t.verificationCategoryPresenter,
      'verificationCategoryActor' => _t.verificationCategoryActor,
      'verificationCategoryDirector' => _t.verificationCategoryDirector,
      'verificationCategoryMusician' => _t.verificationCategoryMusician,
      'verificationCategoryWriter' => _t.verificationCategoryWriter,
      'verificationCategoryArtist' => _t.verificationCategoryArtist,
      'verificationCategoryAthlete' => _t.verificationCategoryAthlete,
      'verificationCategoryCoach' => _t.verificationCategoryCoach,
      'verificationCategoryPolitician' => _t.verificationCategoryPolitician,
      'verificationCategoryDiplomat' => _t.verificationCategoryDiplomat,
      'verificationCategoryAcademic' => _t.verificationCategoryAcademic,
      'verificationCategoryHealthProfessional' => _t.verificationCategoryHealthProfessional,
      'verificationCategoryLegal' => _t.verificationCategoryLegal,
      'verificationCategoryEntrepreneur' => _t.verificationCategoryEntrepreneur,
      'verificationCategoryBusinessManager' => _t.verificationCategoryBusinessManager,
      'verificationCategoryTechnology' => _t.verificationCategoryTechnology,
      'verificationCategoryEducation' => _t.verificationCategoryEducation,
      'verificationCategoryActivist' => _t.verificationCategoryActivist,
      'verificationCategoryRetail' => _t.verificationCategoryRetail,
      'verificationCategoryRestaurant' => _t.verificationCategoryRestaurant,
      'verificationCategoryClinic' => _t.verificationCategoryClinic,
      'verificationCategoryTechnical' => _t.verificationCategoryTechnical,
      'verificationCategoryConstruction' => _t.verificationCategoryConstruction,
      'verificationCategoryTransport' => _t.verificationCategoryTransport,
      'verificationCategoryTourism' => _t.verificationCategoryTourism,
      'verificationCategoryNgo' => _t.verificationCategoryNgo,
      'verificationCategoryCompany' => _t.verificationCategoryCompany,
      'verificationCategoryOther' => _t.verificationCategoryOther,
      _ => category ?? '—',
    };
  }
  String _status = 'pending';
  bool _loading = true;
  List<Map<String,dynamic>> _items = [];
  String? _error;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    setState(()=>_loading=true);
    try { final rows=await AdminService.loadVerificationRequests(status:_status); if(mounted)setState(()=>_items=rows); }
    catch(_){if(mounted)setState(()=>_error=_t.adminVerificationLoadFailed);}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _review(Map<String,dynamic> item,String status) async {
    final note=TextEditingController();
    final title=status=='approved'?_t.adminVerificationApproveTitle:status=='rejected'?_t.adminVerificationRejectTitle:_t.adminVerificationMoreInfoTitle;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:note,maxLines:4,maxLength:2000,decoration:InputDecoration(labelText:_t.adminVerificationNote)),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(_t.feedCancel)),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(_t.adminVerificationSaveDecision))]));
    if(ok!=true)return;
    try {await AdminService.reviewVerification(item['id'].toString(),status,note:note.text); if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_t.adminVerificationUpdated)));_load();}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_t.adminVerificationUpdateFailed)));}
    finally{note.dispose();}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_t.adminVerificationTitle)),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:8,children:[
        for(final status in const ['pending','under_review','needs_info','approved','rejected'])
          ChoiceChip(label:Text(_statusLabel(status)),selected:_status==status,onSelected:(_){setState(()=>_status=status);_load();})
      ])),
      Expanded(child:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):
        _items.isEmpty?Center(child:Text(_t.adminVerificationEmpty)):
        RefreshIndicator(onRefresh:_load,child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:_items.length,itemBuilder:(ctx,i){
          final item=_items[i];final profile=item['profile'] as Map<String,dynamic>? ?? {};
          final links=item['public_links'] as List? ?? const [];final evidence=item['evidence_urls'] as List? ?? const [];
          return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(item['legal_name']?.toString()??_t.adminVerificationNoName,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),
            Text('@${profile['username']??_t.storyUserFallback} • ${item['applicant_type']=='individual'?_t.verificationIndividual:_t.verificationOrganization}'),
            Text('${_t.verificationCategory}: ${_categoryLabel(item['category']?.toString())}'),
            if((item['phone']??'').toString().isNotEmpty)Text('${_t.verificationPhoneOptional}: ${item['phone']}'),
            if((item['organization_registration_number']??'').toString().isNotEmpty)Text('${_t.verificationRegistrationNumber}: ${item['organization_registration_number']}'),
            if((item['organization_national_id']??'').toString().isNotEmpty)Text('${_t.verificationNationalId}: ${item['organization_national_id']}'),
            const SizedBox(height:8),Text(item['explanation']?.toString()??''),
            for(final link in links)SelectableText(link.toString(),style:TextStyle(color:Theme.of(context).colorScheme.primary)),
            if(evidence.isNotEmpty)Wrap(spacing:8,children:[for(final url in evidence)TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(ctx)=>Dialog(child:InteractiveViewer(child:Image.network(url.toString(),fit:BoxFit.contain)))),icon:const Icon(Icons.image_outlined),label:Text(_t.adminVerificationViewEvidence))]),
            const SizedBox(height:8),Wrap(spacing:8,runSpacing:6,children:[
              OutlinedButton(onPressed:()=>_review(item,'under_review'),child:Text(_t.adminVerificationStartReview)),
              OutlinedButton(onPressed:()=>_review(item,'needs_info'),child:Text(_t.adminVerificationRequestInfo)),
              FilledButton(onPressed:()=>_review(item,'approved'),child:Text(_t.adminVerificationApprove)),
              TextButton(onPressed:()=>_review(item,'rejected'),child:Text(_t.adminVerificationReject)),
            ])
          ])));
        }))
      )
    ])
  );
}
