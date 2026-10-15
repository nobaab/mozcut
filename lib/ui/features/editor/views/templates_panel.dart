import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

/// A single row in the template catalogue. Purely presentational — there is
/// no backing asset, engine project, or render pipeline yet. Picking one
/// shows a "coming soon" snackbar; it never touches [Clip] or the project
/// model.
class _TemplateInfo {
  const _TemplateInfo({
    required this.title,
    required this.category,
    required this.aspectRatio,
    required this.clipCount,
    required this.durationSeconds,
  });

  final String title;
  final String category;
  final double aspectRatio;
  final int clipCount;
  final double durationSeconds;

  String get meta {
    final m = durationSeconds ~/ 60;
    final s = (durationSeconds % 60).toInt();
    final time = '$m:${s.toString().padLeft(2, '0')}';
    return '$clipCount clips · $time';
  }
}

/// The filter chips above the grid. Each one is either an aspect-ratio
/// preset (matching how the clip would be framed) or a content category —
/// CapCut mixes both in one row, so this does too.
const _categories = <String>[
  'All',
  '9:16 TikTok/Reels',
  '16:9 YouTube',
  '1:1 Square',
  'Vlog',
  'Ads',
  'Gaming',
];

const _templates = <_TemplateInfo>[
  _TemplateInfo(
      title: 'Trendy Reel Opener',
      category: '9:16 TikTok/Reels',
      aspectRatio: 9 / 16,
      clipCount: 8,
      durationSeconds: 15),
  _TemplateInfo(
      title: 'Quick Product Hook',
      category: '9:16 TikTok/Reels',
      aspectRatio: 9 / 16,
      clipCount: 6,
      durationSeconds: 12),
  _TemplateInfo(
      title: 'Daily Vlog Intro',
      category: 'Vlog',
      aspectRatio: 9 / 16,
      clipCount: 5,
      durationSeconds: 20),
  _TemplateInfo(
      title: 'Story Time Montage',
      category: '9:16 TikTok/Reels',
      aspectRatio: 9 / 16,
      clipCount: 10,
      durationSeconds: 30),
  _TemplateInfo(
      title: 'Cinematic Travel Vlog',
      category: 'Vlog',
      aspectRatio: 16 / 9,
      clipCount: 14,
      durationSeconds: 90),
  _TemplateInfo(
      title: 'YouTube Intro Classic',
      category: '16:9 YouTube',
      aspectRatio: 16 / 9,
      clipCount: 4,
      durationSeconds: 8),
  _TemplateInfo(
      title: 'Tutorial Walkthrough',
      category: '16:9 YouTube',
      aspectRatio: 16 / 9,
      clipCount: 12,
      durationSeconds: 180),
  _TemplateInfo(
      title: 'Weekly Recap',
      category: '16:9 YouTube',
      aspectRatio: 16 / 9,
      clipCount: 9,
      durationSeconds: 120),
  _TemplateInfo(
      title: 'Minimal Product Grid',
      category: '1:1 Square',
      aspectRatio: 1,
      clipCount: 6,
      durationSeconds: 24),
  _TemplateInfo(
      title: 'Feed Post Teaser',
      category: '1:1 Square',
      aspectRatio: 1,
      clipCount: 4,
      durationSeconds: 10),
  _TemplateInfo(
      title: 'Flash Sale Promo',
      category: 'Ads',
      aspectRatio: 9 / 16,
      clipCount: 7,
      durationSeconds: 15),
  _TemplateInfo(
      title: 'App Install CTA',
      category: 'Ads',
      aspectRatio: 1,
      clipCount: 5,
      durationSeconds: 18),
  _TemplateInfo(
      title: 'Before / After Ad',
      category: 'Ads',
      aspectRatio: 16 / 9,
      clipCount: 6,
      durationSeconds: 20),
  _TemplateInfo(
      title: 'Clutch Highlight Reel',
      category: 'Gaming',
      aspectRatio: 16 / 9,
      clipCount: 11,
      durationSeconds: 45),
  _TemplateInfo(
      title: 'Stream Recap Shorts',
      category: 'Gaming',
      aspectRatio: 9 / 16,
      clipCount: 9,
      durationSeconds: 30),
  _TemplateInfo(
      title: 'Top Fragsmoment',
      category: 'Gaming',
      aspectRatio: 1,
      clipCount: 3,
      durationSeconds: 9),
];

/// The Templates tab: a searchable, filterable catalogue of starter
/// templates. Browsing and filtering is fully functional; applying a
/// template is not implemented yet, so selecting one just announces that.
/// This is catalogue UI only — it never reads or writes the Clip/Project
/// model or the render engine.
class TemplatesPanel extends StatefulWidget {
  const TemplatesPanel({super.key});

  @override
  State<TemplatesPanel> createState() => _TemplatesPanelState();
}

class _TemplatesPanelState extends State<TemplatesPanel> {
  String _query = '';
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = _templates.where((t) {
      final matchesCategory = _category == 'All' || t.category == _category;
      final matchesQuery =
          _query.isEmpty || t.title.toLowerCase().contains(_query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: VTextField(
            hint: 'Search templates',
            icon: Icons.search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final category = _categories[i];
              return VChip(
                label: category,
                selected: category == _category,
                onTap: () => setState(() => _category = category),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Templates',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No templates match.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _TemplateCard(template: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template});

  final _TemplateInfo template;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () => ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('"${template.title}" — coming soon'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.well,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.line),
              ),
              padding: const EdgeInsets.all(8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: template.aspectRatio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Icon(Icons.dashboard_outlined,
                          size: 18, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(template.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(template.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}
