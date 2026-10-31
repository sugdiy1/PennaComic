import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comic_preview.dart';
import 'novel_comic_model.dart';

class NovelComicPage extends StatefulWidget {
  const NovelComicPage({super.key,required this.model});
  final NovelComicModel model;
  @override
  State<NovelComicPage> createState()=>_NovelComicPageState();
}

class _NovelComicPageState extends State<NovelComicPage> {
  NovelComicModel get model=>widget.model;
  int _tab=0;
  String? _panel;

  Future<void> _import() async {
    try {
      final file=await openFile(acceptedTypeGroups:[
        const XTypeGroup(label:'小说',extensions:['txt','epub']),
      ]);
      if(file==null || !mounted) return;
      await model.importNovel(file.path);
    } on Object catch(e) { if(mounted) showToast(context,'导入失败：$e',warn:true); }
  }

  Future<void> _plan() async {
    if(model.current?.pages.isNotEmpty==true) {
      final proceed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:Text(tr('重新生成分镜？')),
        content:Text(tr('相同设置会保留现有页；修改生成设置后重新规划会覆盖该作品的分镜改稿。')),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(tr('取消'))),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(tr('继续生成分镜')))],
      ));
      if(proceed!=true || !mounted) return;
    }
    await model.planCurrent();
    if(mounted) setState(() { _tab=0; _panel=null; });
  }

  Future<void> _settings() async {
    var draft=model.options;
    String? problem;
    await showDialog<void>(context:context,builder:(context)=>StatefulBuilder(
      builder:(context,setDialog)=>AlertDialog(
        title:Text(tr('小说漫画设置')),
        content:SizedBox(width:530,child:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            Text(tr('当前只生成分镜计划。生图参数将保存在作品记录中。'),style:TextStyle(fontSize:12,color:PennaColors.slate500)),
            const SizedBox(height:16),
            DropdownButtonFormField<String>(initialValue:draft.style,
              decoration:InputDecoration(labelText:tr('画风')),
              items:const [DropdownMenuItem(value:'mono',child:Text('黑白漫画')),
                DropdownMenuItem(value:'color',child:Text('彩色漫画')),
                DropdownMenuItem(value:'sketch',child:Text('线稿'))],
              onChanged:(value)=>setDialog(()=>draft=draft.copyWith(style:value,
                lora:value=='color' ? 'muqiu_moss.safetensors' : 'moss_Lineart.safetensors'))),
            const SizedBox(height:12),
            Row(children:[Expanded(child:PennaField(label:tr('每章页数'),value:'${draft.pagesPerChapter}',
              onChanged:(v)=>draft=draft.copyWith(pagesPerChapter:int.tryParse(v) ?? 0))),
              const SizedBox(width:12),Expanded(child:DropdownButtonFormField<int>(
                initialValue:draft.panelsPerPage,decoration:InputDecoration(labelText:tr('每页格数')),
                items:[for(final n in [4,5,6])DropdownMenuItem(value:n,child:Text('$n 格'))],
                onChanged:(v)=>draft=draft.copyWith(panelsPerPage:v)))]),
            const SizedBox(height:12),
            PennaField(key:ValueKey('lora-${draft.style}'),label:'LoRA',value:draft.lora,
              onChanged:(v)=>draft=draft.copyWith(lora:v)),
            const SizedBox(height:12),
            Row(children:[Expanded(child:PennaField(label:tr('LoRA 强度'),value:'${draft.loraStrength}',
              onChanged:(v)=>draft=draft.copyWith(loraStrength:double.tryParse(v) ?? -1))),
              const SizedBox(width:12),Expanded(child:PennaField(label:tr('步数'),value:'${draft.steps}',
                onChanged:(v)=>draft=draft.copyWith(steps:int.tryParse(v) ?? 0))),
              const SizedBox(width:12),Expanded(child:PennaField(label:tr('种子'),value:'${draft.seed}',
                onChanged:(v)=>draft=draft.copyWith(seed:int.tryParse(v) ?? -1)))]),
            const SizedBox(height:12),
            PennaField(label:tr('ComfyUI 地址'),value:draft.comfyUrl,onChanged:(v)=>draft=draft.copyWith(comfyUrl:v)),
            const SizedBox(height:16),
            ExpansionTile(title:Text(tr('本地后端'),style:const TextStyle(fontSize:13)),
              tilePadding:EdgeInsets.zero,children:[
                PennaField(label:tr('Python 路径'),value:draft.python,onChanged:(v)=>draft=draft.copyWith(python:v)),
                const SizedBox(height:12),
                PennaField(label:tr('launcher.py 路径'),value:draft.launcher,onChanged:(v)=>draft=draft.copyWith(launcher:v)),
              ]),
            if(problem!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(problem!,style:TextStyle(color:PennaColors.diffDelText))),
          ],
        ))),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(tr('取消'))),
          FilledButton(onPressed:(){
            try { model.setOptions(draft); Navigator.pop(context); }
            on Object catch(e) { setDialog(()=>problem='$e'); }
          },child:Text(tr('保存')))],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable:model,builder:(context,_) {
    final current=model.current;
    return ColoredBox(color:PennaColors.bg,child:Column(children:[
      PennaBar(color:PennaColors.card,children:[
        Icon(Icons.auto_stories_outlined,size:17,color:PennaColors.primary),
        const SizedBox(width:7),Text(tr('小说漫画'),style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
        const SizedBox(width:12),
        if(current!=null)Expanded(child:Text(current.name,maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:12,color:PennaColors.slate500))) else const Spacer(),
        PennaButton(label:tr('导入小说'),icon:Icons.upload_file_outlined,onPressed:model.busy ? null : _import),
        const SizedBox(width:6),
        PennaButton(label:tr('生成分镜'),icon:Icons.view_quilt_outlined,
          background:PennaColors.primaryBg,foreground:PennaColors.primary,
          onPressed:current==null || model.busy ? null : _plan),
        const SizedBox(width:6),
        PennaButton(label:'',icon:Icons.tune,tooltip:tr('小说漫画设置'),onPressed:model.busy ? null : _settings),
      ]),
      if(model.busy)const LinearProgressIndicator(minHeight:2),
      if(model.error!=null)Container(width:double.infinity,color:PennaColors.diffDel,
        padding:const EdgeInsets.all(10),child:SelectableText(model.error!,style:TextStyle(fontSize:12,color:PennaColors.diffDelText))),
      Expanded(child:LayoutBuilder(builder:(context,constraints) {
        final wide=constraints.maxWidth>=1120;
        return Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          SizedBox(width:constraints.maxWidth<850 ? 180 : 226,child:_library()),
          VerticalDivider(width:1,color:PennaColors.border),
          Expanded(child:current==null ? _empty() : _workspace(wide)),
          if(wide && model.page!=null) ...[
            VerticalDivider(width:1,color:PennaColors.border),
            SizedBox(width:320,child:_inspector()),
          ],
        ]);
      })),
      Container(height:30,color:PennaColors.card,padding:const EdgeInsets.symmetric(horizontal:14),
        child:Row(children:[Icon(Icons.edit_note,size:14,color:PennaColors.slate500),
          const SizedBox(width:6),Expanded(child:Text(
            model.busy ? tr('正在解析小说并生成分镜…') : tr('框架阶段 · 台词由程序排字 · 生图队列待接入'),
            style:TextStyle(fontSize:11,color:PennaColors.slate500))),
          if(current!=null)Text('${current.pages.length} 页分镜',style:TextStyle(fontSize:11,color:PennaColors.slate500)),
        ])),
    ]));
  });

  Widget _empty()=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(
    mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.auto_stories_outlined,size:48,color:PennaColors.primary),
      const SizedBox(height:20),Text(tr('从一部小说开始'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w600)),
      const SizedBox(height:10),Text(tr('导入 TXT 或 EPUB，按卷章整理内容，再生成可编辑的漫画分镜。'),
        textAlign:TextAlign.center,style:TextStyle(fontSize:13,color:PennaColors.slate500,height:1.7)),
      const SizedBox(height:24),PennaButton(label:tr('导入小说'),icon:Icons.upload_file_outlined,
        background:PennaColors.primaryBg,foreground:PennaColors.primary,onPressed:_import),
    ],
  )));

  Widget _library() {
    final project=model.current;
    return ColoredBox(color:PennaColors.card,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(14,16,14,8),child:Text(tr('作品'),style:TextStyle(fontSize:12,color:PennaColors.slate500))),
      if(model.projects.isEmpty)Padding(padding:const EdgeInsets.all(14),child:Text(tr('导入后在这里管理卷章和页面'),
        style:TextStyle(fontSize:12,color:PennaColors.slate400,height:1.6))),
      if(model.projects.isNotEmpty)ConstrainedBox(constraints:const BoxConstraints(maxHeight:180),
        child:ListView(shrinkWrap:true,children:[for(final p in model.projects)ListTile(dense:true,selected:p.id==project?.id,
        selectedTileColor:PennaColors.primaryBg,
        leading:Icon(Icons.menu_book,size:18,color:PennaColors.primary),
        title:Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
        subtitle:Text(p.pages.isEmpty ? tr('等待规划') : '${p.pages.length} 页分镜',style:const TextStyle(fontSize:10)),
        onTap:model.busy ? null : ()=>model.selectProject(p.id))])),
      Divider(height:24,color:PennaColors.border),
      Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Text(tr('卷章 / 页面'),style:TextStyle(fontSize:12,color:PennaColors.slate500))),
      const SizedBox(height:8),
      Expanded(child:project==null || project.pages.isEmpty ? const SizedBox() : ListView(
        children:[for(final volume in project.pages.map((p)=>p.volume).toSet())
          ExpansionTile(initiallyExpanded:true,dense:true,tilePadding:const EdgeInsets.symmetric(horizontal:12),
            title:Text(volume,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600)),
            children:[for(final chapter in project.pages.where((p)=>p.volume==volume).map((p)=>p.chapter).toSet())
              ExpansionTile(initiallyExpanded:true,dense:true,tilePadding:const EdgeInsets.only(left:20,right:10),
                title:Text(chapter,style:const TextStyle(fontSize:11)),
                children:[for(final p in project.pages.where((p)=>p.volume==volume && p.chapter==chapter))
                  ListTile(dense:true,contentPadding:const EdgeInsets.only(left:32,right:10),
                    selected:model.currentPage?.id==p.id,selectedTileColor:PennaColors.primaryBg,
                    title:Text(p.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
                    trailing:Icon(Icons.radio_button_unchecked,size:12,color:PennaColors.slate400),
                    onTap:model.busy ? null : (){_panel=null;model.selectPage(p.id);}),
                ]),
            ]),
        ],
      )),
    ]));
  }

  Widget _workspace(bool wide) {
    if(model.page==null) {
      return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(Icons.view_quilt_outlined,size:42,color:PennaColors.slate400),
        const SizedBox(height:16),Text(tr('小说已导入'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
        const SizedBox(height:10),Text(tr('点击“生成分镜”拆分卷章和漫画页。'),style:TextStyle(color:PennaColors.slate500)),
        const SizedBox(height:12),SelectableText(model.current!.inputPath,style:TextStyle(fontSize:11,color:PennaColors.slate400)),
      ])));
    }
    final panels=_items('panel');
    final selected=panels.where((p)=>p['id']==_panel).firstOrNull ?? panels.firstOrNull;
    return Column(children:[
      Container(height:45,color:PennaColors.card,child:Row(children:[
        const SizedBox(width:10),
        for(final entry in [(0,'漫画页'),(1,'原文'),(2,'分镜编辑'),(3,'待生成')])
          Padding(padding:const EdgeInsets.only(right:4),child:TextButton(
            onPressed:()=>setState(()=>_tab=entry.$1),
            style:TextButton.styleFrom(foregroundColor:_tab==entry.$1 ? PennaColors.primary : PennaColors.slate500),
            child:Text(tr(entry.$2),style:const TextStyle(fontSize:12)))),
      ])),
      Expanded(child:switch(_tab) {
        1=>SingleChildScrollView(padding:const EdgeInsets.all(28),child:SelectableText(
          panels.map((p)=>p['source_text'] as String? ?? '').join('\n\n'),
          style:TextStyle(fontFamily:bundledCjkFont,fontSize:14,height:1.9,color:PennaColors.text))),
        2=>_inspector(all:true),
        3=>_queue(),
        _=>ComicPreview(page:model.page!,selected:selected?['id'] as String?,onSelect:(id)=>setState((){
          _panel=id; if(!wide) _tab=2;
        })),
      }),
      if(model.current!.warnings.isNotEmpty)Padding(padding:const EdgeInsets.all(10),child:Text(
        model.current!.warnings.join('\n'),maxLines:3,overflow:TextOverflow.ellipsis,
        style:TextStyle(fontSize:11,color:PennaColors.lockText))),
    ]);
  }

  List<Map<String,dynamic>> _items(String type)=>[
    for(final raw in model.page?['items'] as List? ?? [])
      if(raw['type']==type)Map<String,dynamic>.from(raw as Map),
  ];

  Widget _inspector({bool all=false}) {
    final panels=_items('panel');
    final selected=panels.where((p)=>p['id']==_panel).firstOrNull ?? panels.firstOrNull;
    final shown=all ? panels : [?selected];
    return ColoredBox(color:PennaColors.card,child:ListView(padding:const EdgeInsets.all(16),children:[
      Row(children:[Text(tr('分镜与台词'),style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
        const Spacer(),PennaButton(label:tr('复制 JSON'),icon:Icons.copy,onPressed:model.page==null ? null : () async {
          await Clipboard.setData(ClipboardData(text:const JsonEncoder.withIndent('  ').convert(model.page)));
          if(mounted) showToast(context,tr('已复制页面 JSON'));
        })]),
      const SizedBox(height:8),Text(tr('修改后自动保存。画面生成前可逐格检查。'),style:TextStyle(fontSize:11,color:PennaColors.slate500)),
      if(!all) ...[
        const SizedBox(height:12),Wrap(spacing:6,runSpacing:6,children:[
          for(var n=0;n<panels.length;n++)ChoiceChip(label:Text('${n+1}'),selected:panels[n]['id']==selected?['id'],
            onSelected:(_)=>setState(()=>_panel=panels[n]['id'] as String)),
        ]),
      ],
      for(final panel in shown) ...[
        const SizedBox(height:18),Text('第 ${panels.indexOf(panel)+1} 格 · ${panel['shape']}',style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:PennaColors.primary)),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(key:ValueKey('${model.currentPage?.id}-${panel['id']}-camera'),
          initialValue:panel['camera'] as String? ?? 'wide',decoration:InputDecoration(labelText:tr('镜头')),
          items:[for(final entry in [('wide','全景'),('medium','中景'),('close','特写'),('low','仰视')])
            DropdownMenuItem(value:entry.$1,child:Text(entry.$2))],
          onChanged:(value){if(value!=null)model.editItem(panel['id'] as String,'camera',value);}),
        const SizedBox(height:12),
        PennaField(key:ValueKey('${model.currentPage?.id}-${panel['id']}-desc'),label:tr('画面描述'),
          value:panel['desc'] as String? ?? '',maxLines:7,
          onChanged:(value)=>model.editItem(panel['id'] as String,'desc',value)),
        const SizedBox(height:12),
        for(final bubble in _items('bubble').where((b)=>b['panel_id']==panel['id'])) ...[
          PennaField(key:ValueKey('${model.currentPage?.id}-${bubble['id']}-text'),label:tr('中文台词'),
            value:bubble['text'] as String? ?? '',maxLines:3,
            onChanged:(value)=>model.editItem(bubble['id'] as String,'text',value)),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(key:ValueKey('${model.currentPage?.id}-${bubble['id']}-kind'),
            initialValue:bubble['kind'] as String? ?? 'speech-notail',decoration:InputDecoration(labelText:tr('气泡')),
            items:[for(final entry in [('speech-notail','画外对白'),('speech','椭圆对白'),('thought','云朵内心'),('shout','锯齿喊叫'),('narration','旁白')])
              DropdownMenuItem(value:entry.$1,child:Text(entry.$2))],
            onChanged:(value){if(value!=null)model.editItem(bubble['id'] as String,'kind',value);}),
          const SizedBox(height:14),
        ],
        ExpansionTile(tilePadding:EdgeInsets.zero,title:Text(tr('本格原文'),style:const TextStyle(fontSize:12)),
          children:[SelectableText(panel['source_text'] as String? ?? '',style:TextStyle(fontSize:12,height:1.7,color:PennaColors.slate500))]),
        Divider(color:PennaColors.border),
      ],
    ]));
  }

  Widget _queue()=>ListView(padding:const EdgeInsets.all(20),children:[
    Text(tr('待生成页面'),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
    const SizedBox(height:10),Text(tr('分镜已准备好，批量生图将在下一阶段接入。'),style:TextStyle(fontSize:12,color:PennaColors.slate500)),
    const SizedBox(height:16),
    for(final p in model.current!.pages)ListTile(dense:true,
      leading:Icon(Icons.hourglass_empty,size:18,color:PennaColors.slate400),
      title:Text(p.title,style:const TextStyle(fontSize:12)),
      subtitle:Text('${p.volume} / ${p.chapter}',style:const TextStyle(fontSize:11)),
      trailing:Text(tr('待生成'),style:TextStyle(fontSize:11,color:PennaColors.slate500))),
    const SizedBox(height:18),Text(tr('作品输出目录'),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600)),
    const SizedBox(height:6),SelectableText(model.current!.outputPath,style:TextStyle(fontSize:11,color:PennaColors.slate500)),
  ]);
}
