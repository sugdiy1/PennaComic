import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/novel_comic_backend.dart';
import 'package:penna/data/models/novel_comic.dart';
import 'package:penna/ui/features/comic/novel_comic_model.dart';
import 'package:penna/ui/features/comic/novel_comic_page.dart';

class _OfflineBackend implements NovelComicBackend {
  @override
  Future<Map<String, dynamic>> plan({
    required String input,
    required String output,
    required ComicOptions options,
  }) async {
    final pageFile = File('$output/book/volume/p0001/page.json');
    pageFile.parent.createSync(recursive: true);
    pageFile.writeAsStringSync(jsonEncode({
      'id': 'p01', 'size': [1024,1536], 'style':'mono',
      'items': [
        {'type':'panel','id':'pn_01','bbox':[16,16,1008,400],
         'camera':'wide','shape':'rect','desc':'A rainy gate','source_text':'城门外下起大雨。'},
        {'type':'bubble','id':'b_01','panel_id':'pn_01','bbox':[800,50,980,300],
         'text':'你终于来了！','kind':'speech-notail'},
      ],
    }));
    return {
      'book':'测试作品','stage':'planned','total_pages':1,'completed_pages':0,
      'pages':[
        {'id':'p01','title':'相遇','volume':'第一卷','chapter':'第一章',
         'page_json':'book/volume/p0001/page.json','status':'planned'},
      ],
      'warnings':[],
    };
  }
}

void main() {
  late Directory dir;
  setUp(() { dir=Directory.systemTemp.createTempSync('penna-comic-'); });
  tearDown(() { dir.deleteSync(recursive:true); });

  test('导入与生成离线分镜后仍为待生成，不声称已经渲染', () async {
    final input=File('${dir.path}/小说.txt')..writeAsStringSync('第一章\n城门外下起大雨。');
    final model=NovelComicModel(dir:dir,backend:_OfflineBackend());
    await model.importNovel(input.path);
    expect(model.current!.status,'imported');
    await model.planCurrent();
    expect(model.current!.name,'测试作品');
    expect(model.current!.status,'planned');
    expect(model.current!.pages.single.status,'planned');
    expect(model.page!['items'],hasLength(2));
    expect(dir.listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.png')),isEmpty);
    model.dispose();
  });

  test('编辑分镜写回原页文件，重启工作区仍能读回', () async {
    final input=File('${dir.path}/小说.txt')..writeAsStringSync('原文');
    final model=NovelComicModel(dir:dir,backend:_OfflineBackend());
    await model.importNovel(input.path);
    await model.planCurrent();
    model.editItem('pn_01','desc','A moonlit gate');
    final json=jsonDecode(resolveComicArtifact(model.current!.outputPath,model.current!.pages.single.pageJson).readAsStringSync());
    expect(json['items'][0]['desc'],'A moonlit gate');
    model.dispose();
    final back=NovelComicModel(dir:dir,backend:_OfflineBackend());
    await back.load();
    expect(back.current!.pages,hasLength(1));
    expect((back.page!['items'] as List)[0]['desc'],'A moonlit gate');
    back.dispose();
  });

  test('后端返回的文件路径不能逃出作品输出目录', () {
    expect(()=>resolveComicArtifact(dir.path,'../../secret.json'),throwsFormatException);
    expect(()=>resolveComicArtifact(dir.path,r'C:\secret.json'),throwsFormatException);
  });

  testWidgets('工作区空态可以导入小说且出图按钮不启动任务', (tester) async {
    final model=NovelComicModel(dir:dir,backend:_OfflineBackend());
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:NovelComicPage(model:model))));
    expect(find.text('小说漫画'),findsOneWidget);
    expect(find.text('导入小说'),findsWidgets);
    expect(find.textContaining('导入 TXT 或 EPUB'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
