import 'package:sqflite/sqflite.dart';
import 'report_queue_schema.dart';

/// v17 expands inspection provenance without attributing any existing row.
class InspectionOwnershipSchema {
  static const tables = {
    'local_jobs', 'local_inspections', 'local_photos',
    'pending_actions', 'inspection_job_retention', 'sync_log_entries',
  };

  static Future<void> applyV17(DatabaseExecutor db) async {
    for (final table in tables) {
      await ReportQueueSchema.addColumnIfMissing(db, table, 'inspector_id', 'TEXT');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_inspector '
          'ON $table(inspector_id)');
    }
  }
}
