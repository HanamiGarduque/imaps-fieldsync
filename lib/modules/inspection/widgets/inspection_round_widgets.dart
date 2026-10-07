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

/// Compact round context container for Task Overview.
///
/// Contextual information only: it renders the round the server already
/// authored and nothing else. It is NOT a control - no tap, no mutation, no
/// decision. Planning Review reason/date stay in [ReinspectionContextCard].
class RoundContextCard extends StatelessWidget {
  final TaskItem task;
  final bool readOnly;

  const RoundContextCard({super.key, required this.task, this.readOnly = false});

  Color get _statusColor => switch (task.category) {
        'Completed' => InsightTheme.green,
        'Ongoing' => InsightTheme.blue1,
        _ => InsightTheme.amber,
      };

  @override
  Widget build(BuildContext context) {
    // The round number on its own line; "Reinspection" is the kind line below
    // it. Never compose them into one label here.
    final round = task.inspectionRoundNumber;
    return Container(
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('INSPECTION ROUND',
                    style: InsightTheme.jetBrains(10,
                        w: FontWeight.w700, c: InsightTheme.ink3, ls: 1.0)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(task.category,
                    style: InsightTheme.inter(11,
                        w: FontWeight.w700, c: _statusColor)),
              ),
              if (readOnly) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: InsightTheme.line),
                  ),
                  child: Text('Read only',
                      style: InsightTheme.inter(11,
                          w: FontWeight.w600, c: InsightTheme.ink3)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // The round number on its own line; "Reinspection" is the kind line
          // below it. Never compose them into one label here.
          Text(round != null && round > 0 ? 'Round $round' : 'Inspection',
              style: InsightTheme.poppins(15, w: FontWeight.w700)),
          const SizedBox(height: 2),
          // Authoritative kind: a first round is never presented as a
          // reinspection, and a reinspection never hides that it is one.
          Text(task.isReinspection ? 'Reinspection' : 'Original Inspection',
              style: InsightTheme.inter(11.5, c: InsightTheme.ink2)),
          const SizedBox(height: 2),
          Text(task.inspectionNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: InsightTheme.jetBrains(11, c: InsightTheme.ink3)),
        ],
      ),
    );
  }
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
