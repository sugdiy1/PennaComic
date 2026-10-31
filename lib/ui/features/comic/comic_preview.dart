import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// 框架阶段显示真实 bbox 和气泡文字，空白画面明确标为待生成。
class ComicPreview extends StatelessWidget {
  const ComicPreview({super.key, required this.page, required this.selected,
    required this.onSelect});
  final Map<String,dynamic> page;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final dimensions=(page['size'] as List).cast<num>();
    final width=dimensions[0].toDouble(), height=dimensions[1].toDouble();
    final panels=[for(final i in page['items'] as List)
      if(i['type']=='panel') Map<String,dynamic>.from(i as Map)];
    return LayoutBuilder(builder:(context,constraints) {
      final scale=math.max(.01, math.min((constraints.maxWidth-32)/width,
        (constraints.maxHeight-32)/height)).toDouble();
      return Center(child:SizedBox(width:width*scale,height:height*scale,
        child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onTapUp:(event) {
            final point=event.localPosition/scale;
            for(final panel in panels.reversed) {
              if(_panelPath(panel).contains(point)) { onSelect(panel['id'] as String); break; }
            }
          },
          child:CustomPaint(painter:_PagePainter(page,selected,scale)),
        ),
      ));
    });
  }
}

Path _panelPath(Map<String,dynamic> panel) {
  final b=(panel['bbox'] as List).cast<num>();
  final r=Rect.fromLTRB(b[0].toDouble(),b[1].toDouble(),b[2].toDouble(),b[3].toDouble());
  final p=Path();
  switch(panel['shape']) {
    case 'circle': p.addOval(r); break;
    case 'slant-top':
      p.moveTo(r.left,r.top+r.height*.09); p.lineTo(r.right,r.top);
      p.lineTo(r.right,r.bottom); p.lineTo(r.left,r.bottom); p.close(); break;
    case 'slant-side':
      p.moveTo(r.left+r.width*.09,r.top); p.lineTo(r.right,r.top);
      p.lineTo(r.right-r.width*.09,r.bottom); p.lineTo(r.left,r.bottom); p.close(); break;
    default: p.addRect(r);
  }
  return p;
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.page,this.selected,this.scale);
  final Map<String,dynamic> page;
  final String? selected;
  final double scale;

  void _text(Canvas canvas,String text,Offset at,double fontSize,Color color,
    {double maxWidth=500}) {
    final painter=TextPainter(text:TextSpan(text:text,style:TextStyle(
      fontSize:fontSize,color:color,fontFamily:bundledCjkFont,height:1.35)),
      textDirection:TextDirection.ltr)..layout(maxWidth:maxWidth);
    painter.paint(canvas,at);
    painter.dispose();
  }

  @override
  void paint(Canvas canvas,Size size) {
    canvas.scale(scale);
    final dims=(page['size'] as List).cast<num>();
    canvas.drawRect(Rect.fromLTWH(0,0,dims[0].toDouble(),dims[1].toDouble()),Paint()..color=Colors.white);
    var number=0;
    for(final raw in page['items'] as List) {
      final item=Map<String,dynamic>.from(raw as Map);
      if(item['type']!='panel') continue;
      number++;
      final path=_panelPath(item);
      final rect=path.getBounds();
      final active=item['id']==selected;
      canvas.drawPath(path,Paint()..color=active ? const Color(0xFFEFF6FF) : const Color(0xFFF4F5F7));
      canvas.drawPath(path,Paint()..color=active ? const Color(0xFF2563EB) : const Color(0xFF444D5D)
        ..style=PaintingStyle.stroke..strokeWidth=active ? 5 : 3);
      _text(canvas,'第 $number 格',Offset(rect.left+24,rect.bottom-90),25,const Color(0xFF64748B));
      _text(canvas,'画面待生成',Offset(rect.left+24,rect.bottom-52),20,const Color(0xFF94A3B8));
    }
    for(final raw in page['items'] as List) {
      if(raw['type']!='bubble') continue;
      final b=(raw['bbox'] as List).cast<num>();
      final box=Rect.fromLTRB(b[0].toDouble(),b[1].toDouble(),b[2].toDouble(),b[3].toDouble());
      if(raw['kind']=='narration') {
        canvas.drawRect(box,Paint()..color=Colors.white);
        canvas.drawRect(box,Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth=2);
      } else {
        canvas.drawOval(box,Paint()..color=Colors.white);
        canvas.drawOval(box,Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth=2);
      }
      final text=(raw['text'] as String? ?? '').replaceAll('\n','');
      var font=30.0;
      while(font>12) {
        final rows=math.max(1,(box.height*.64/(font*1.15)).floor());
        final cols=(text.runes.length/rows).ceil();
        if(cols*font*1.2<=box.width*.64) break;
        font--;
      }
      final chars=text.runes.map(String.fromCharCode).toList();
      final rows=math.max(1,(box.height*.64/(font*1.15)).floor());
      final cols=(chars.length/rows).ceil();
      final right=box.center.dx+cols*font*1.2/2-font;
      for(var i=0;i<chars.length;i++) {
        _text(canvas,chars[i],Offset(right-(i~/rows)*font*1.2,
          box.top+box.height*.18+(i%rows)*font*1.15),font,Colors.black,maxWidth:font*1.3);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) => old.page!=page || old.selected!=selected || old.scale!=scale;
}
