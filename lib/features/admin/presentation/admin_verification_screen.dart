import 'package:flutter/material.dart';
import '../data/admin_service.dart';

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});
  @override
  State<AdminVerificationScreen> createState() => _AdminVerificationScreenState();
}
class _AdminVerificationScreenState extends State<AdminVerificationScreen> {
  String _status = 'pending';
  bool _loading = true;
  List<Map<String,dynamic>> _items = [];
  String? _error;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    setState(()=>_loading=true);
    try { final rows=await AdminService.loadVerificationRequests(status:_status); if(mounted)setState(()=>_items=rows); }
    catch(_){if(mounted)setState(()=>_error='دریافت درخواست‌ها انجام نشد.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _review(Map<String,dynamic> item,String status) async {
    final note=TextEditingController();
    final title=status=='approved'?'تأیید درخواست':status=='rejected'?'رد درخواست':'درخواست اطلاعات بیشتر';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:note,maxLines:4,maxLength:2000,decoration:const InputDecoration(labelText:'یادداشت برای کاربر (اختیاری)')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ثبت تصمیم'))]));
    if(ok!=true)return;
    try {await AdminService.reviewVerification(item['id'].toString(),status,note:note.text); if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('وضعیت درخواست به‌روزرسانی شد.')));_load();}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ثبت تصمیم انجام نشد.')));}
    finally{note.dispose();}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('درخواست‌های نشان تأیید')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:8,children:[
        for(final e in const [('pending','در انتظار'),('under_review','در حال بررسی'),('needs_info','نیازمند اطلاعات'),('approved','تأییدشده'),('rejected','ردشده')])
          ChoiceChip(label:Text(e.$2),selected:_status==e.$1,onSelected:(_){setState(()=>_status=e.$1);_load();})
      ])),
      Expanded(child:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):
        _items.isEmpty?const Center(child:Text('درخواستی در این دسته وجود ندارد.')):
        RefreshIndicator(onRefresh:_load,child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:_items.length,itemBuilder:(ctx,i){
          final item=_items[i];final profile=item['profile'] as Map<String,dynamic>? ?? {};
          final links=item['public_links'] as List? ?? const [];final evidence=item['evidence_urls'] as List? ?? const [];
          return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(item['legal_name']?.toString()??'بدون نام',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),
            Text('@${profile['username']??'unknown'} • ${item['applicant_type']=='individual'?'شخص حقیقی':'شخص حقوقی'}'),
            Text('حوزه: ${item['category']??'—'}'),
            if((item['phone']??'').toString().isNotEmpty)Text('تماس: ${item['phone']}'),
            if((item['organization_registration_number']??'').toString().isNotEmpty)Text('شماره ثبت: ${item['organization_registration_number']}'),
            if((item['organization_national_id']??'').toString().isNotEmpty)Text('شناسه ملی: ${item['organization_national_id']}'),
            const SizedBox(height:8),Text(item['explanation']?.toString()??''),
            for(final link in links)SelectableText(link.toString(),style:TextStyle(color:Theme.of(context).colorScheme.primary)),
            if(evidence.isNotEmpty)Wrap(spacing:8,children:[for(final url in evidence)TextButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(ctx)=>Dialog(child:InteractiveViewer(child:Image.network(url.toString(),fit:BoxFit.contain)))),icon:const Icon(Icons.image_outlined),label:const Text('مشاهده مدرک'))]),
            const SizedBox(height:8),Wrap(spacing:8,runSpacing:6,children:[
              OutlinedButton(onPressed:()=>_review(item,'under_review'),child:const Text('شروع بررسی')),
              OutlinedButton(onPressed:()=>_review(item,'needs_info'),child:const Text('اطلاعات بیشتر')),
              FilledButton(onPressed:()=>_review(item,'approved'),child:const Text('تأیید')),
              TextButton(onPressed:()=>_review(item,'rejected'),child:const Text('رد درخواست')),
            ])
          ])));
        }))
      )
    ])
  );
}
