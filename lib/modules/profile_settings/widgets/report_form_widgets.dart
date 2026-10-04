import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/report_models.dart';
import '../../../core/theme/insight_theme.dart';

// Feature-local recipes using Profile's input treatment and canonical tokens.
// The Scaffold already resizes above the keyboard; don't add that inset twice.
EdgeInsets reportPagePadding(BuildContext context) {
  final media = MediaQuery.of(context);
  final gutter = math.max(
    20.0,
    (media.size.width - media.padding.horizontal - 640) / 2,
  );
  return EdgeInsets.fromLTRB(gutter, 16, gutter, 32);
}

InputDecoration reportInputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintMaxLines: 3,
  hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
  filled: true,
  fillColor: InsightTheme.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  constraints: const BoxConstraints(minHeight: 56),
  border: OutlineInputBorder(borderRadius: InsightTheme.roundedSm),
  enabledBorder: OutlineInputBorder(
    borderRadius: InsightTheme.roundedSm,
    borderSide: const BorderSide(color: InsightTheme.lineStrong),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: InsightTheme.roundedSm,
    borderSide: const BorderSide(color: InsightTheme.blue1, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: InsightTheme.roundedSm,
    borderSide: const BorderSide(color: InsightTheme.red),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: InsightTheme.roundedSm,
    borderSide: const BorderSide(color: InsightTheme.red, width: 1.5),
  ),
  errorStyle: InsightTheme.inter(12, c: InsightTheme.redInk),
  errorMaxLines: 4,
);

class ReportFieldLabel extends StatelessWidget {
  const ReportFieldLabel(this.text, {super.key, this.required = true});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      required ? '$text *' : '$text (optional)',
      style: InsightTextStyles.formLabel(),
    ),
  );
}

class ReportTextField extends StatefulWidget {
  const ReportTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    this.required = true,
    this.maxLines = 4,
    this.minLines = 2,
    this.textInputAction = TextInputAction.newline,
    this.enabled = true,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool required;
  final int maxLines;
  final int minLines;
  final TextInputAction textInputAction;
  final bool enabled;

  @override
  State<ReportTextField> createState() => _ReportTextFieldState();
}

class _ReportTextFieldState extends State<ReportTextField> {
  bool _pasteRejected = false;
  late final _pasteGuard = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final reject = newValue.text.length > ReportInput.editingLimit;
    if (_pasteRejected != reject) setState(() => _pasteRejected = reject);
    // Refuse the entire pathological edit. No silent truncation or broken
    // emoji/composing sequence; the pre-paste draft and selection survive.
    return reject ? oldValue : newValue;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: ReportFieldLabel(widget.label, required: widget.required),
      ),
      Semantics(
        label:
            '${widget.label}${widget.required ? ', required' : ', optional'}',
        child: TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: TextInputType.multiline,
          textInputAction: widget.textInputAction,
          textCapitalization: TextCapitalization.sentences,
          style: InsightTextStyles.bodySecondary(color: InsightTheme.ink),
          inputFormatters: [_pasteGuard],
          forceErrorText: _pasteRejected ? ReportInput.tooLong : null,
          validator: widget.validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: reportInputDecoration(widget.hint),
        ),
      ),
    ],
  );
}

/// Native Form validation, then reveal the first affected control. Keeping all
/// fields mounted in the form's scrolling Column also validates offscreen input.
bool validateReportForm(GlobalKey<FormState> key) {
  final invalid = key.currentState!.validateGranularly();
  if (invalid.isEmpty) return true;
  Scrollable.ensureVisible(
    invalid.first.context,
    alignment: 0.15,
    duration: const Duration(milliseconds: 200),
  );
  return false;
}

class ReportSubmitButton extends StatelessWidget {
  const ReportSubmitButton({
    super.key,
    required this.submitting,
    required this.onPressed,
  });
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: submitting ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: InsightTheme.blue1,
        foregroundColor: Colors.white,
        disabledBackgroundColor: InsightTheme.blue2,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedMd),
        textStyle: InsightTextStyles.buttonPrimary(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (submitting) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              submitting ? 'Submitting…' : 'Submit report',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
}

class ReportNotice extends StatelessWidget {
  const ReportNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: error,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? InsightTheme.redTint : InsightTheme.blueTint,
        borderRadius: InsightTheme.roundedSm,
        border: Border.all(
          color: error
              ? InsightTheme.red.withValues(alpha: 0.25)
              : InsightTheme.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 20,
            color: error ? InsightTheme.redInk : InsightTheme.blueInk,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: InsightTheme.inter(
                13,
                c: error ? InsightTheme.redInk : InsightTheme.ink2,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ReportOfflineNote extends StatelessWidget {
  const ReportOfflineNote({super.key});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.offline_bolt_outlined,
        size: 18,
        color: InsightTheme.greenInk,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Saved on this device first. If you are offline, it waits here until you reconnect.',
          style: InsightTextStyles.caption(),
        ),
      ),
    ],
  );
}
