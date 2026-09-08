import 'package:flutter/material.dart';

class FaqItem {
  final String questionEn;
  final String questionTl;
  final String answerEn;
  final String answerTl;

  const FaqItem({
    required this.questionEn,
    required this.questionTl,
    required this.answerEn,
    required this.answerTl,
  });
}

class FaqCategory {
  final String titleEn;
  final String titleTl;
  final IconData icon;
  final List<FaqItem> items;

  const FaqCategory({
    required this.titleEn,
    required this.titleTl,
    required this.icon,
    required this.items,
  });
}
