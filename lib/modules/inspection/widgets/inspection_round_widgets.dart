import 'package:flutter/material.dart';
import '../../../core/theme/insight_theme.dart';
import '../../tasks/screens/tasks_screen.dart';

String formatPlanningReviewDate(String raw) {
  final date=DateTime.tryParse(raw)?.toLocal();
  if(date==null) return raw;
  const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final hour=date.hour%12==0?12:date.hour%12;
  return '${months[date.month-1]} ${date.day}, ${date.year} · $hour:${date.minute.toString().padLeft(2,'0')} ${date.hour>=12?'PM':'AM'}';
}

class ReinspectionContextCard extends StatelessWidget {
  final TaskItem task;
  final List<TaskItem> rounds;
  const ReinspectionContextCard({super.key,required this.task,this.rounds=const []});
  @override
  Widget build(BuildContext context) {
    if(!task.isReinspection || (task.previousSiteInspectionId==null &&
      task.reinspectionReason==null && task.reinspectionReviewedAt==null)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(color:InsightTheme.surface,
        borderRadius:BorderRadius.circular(12),border:Border.all(color:InsightTheme.line)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Planning Review',style:InsightTheme.poppins(14,w:FontWeight.w600)),
        const SizedBox(height:8),
        Text('Requires Reinspection',style:InsightTheme.inter(13,w:FontWeight.w700)),
        if(task.reinspectionReason?.trim().isNotEmpty==true)...[
          const SizedBox(height:8),
          Text('Reason:',style:InsightTheme.inter(12,w:FontWeight.w600)),
          Text(task.reinspectionReason!,style:InsightTheme.inter(13)),
        ],
        if(task.reinspectionReviewedAt?.isNotEmpty==true)...[
          const SizedBox(height:8),
          Text('Reviewed: ${formatPlanningReviewDate(task.reinspectionReviewedAt!)}',style:InsightTheme.inter(12)),
        ],
        if(task.previousSiteInspectionId!=null)...[
          const SizedBox(height:8),
          Text('Previous inspection: ${task.previousRoundLabel(rounds)}',style:InsightTheme.inter(12)),
        ],
        const SizedBox(height:8),
        Text('Read-only record from the City Planning Office.',style:InsightTheme.inter(11,c:InsightTheme.ink3)),
      ]),
    );
  }
}

class InspectionRoundList extends StatelessWidget {
  final List<TaskItem> rounds;
  final ValueChanged<TaskItem> onOpen;
  const InspectionRoundList({super.key,required this.rounds,required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final ordered=List<TaskItem>.of(rounds)..sort((a,b) {
      final activeA=a.lifecycleCategory!=TaskLifecycleCategory.completed;
      final activeB=b.lifecycleCategory!=TaskLifecycleCategory.completed;
      if(activeA!=activeB) return activeA?-1:1;
      return (b.inspectionRoundNumber??0).compareTo(a.inspectionRoundNumber??0);
    });
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Inspection rounds',style:InsightTheme.inter(12,w:FontWeight.w700)),
      for(final round in ordered) ListTile(
        key:ValueKey('round-entry-${round.id}'),contentPadding:EdgeInsets.zero,
        title:Text(round.roundLabel??'Inspection',style:InsightTheme.inter(13,w:FontWeight.w600)),
        subtitle:Text('${round.category}${round.submittedAt!=null && round.category=='Completed' ? ' · ${formatPlanningReviewDate(round.submittedAt!)}' : ''}',style:InsightTheme.inter(12)),
        trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>onOpen(round),
      ),
    ]);
  }
}
