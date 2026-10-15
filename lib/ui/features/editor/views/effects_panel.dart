import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

/// A single entry in the effects catalogue: a name and the category it's
/// filed under (matching Concat's built-in video-effect categories, see
/// docs/FEATURES.md Appendix).
class VideoEffect {
  const VideoEffect(this.name, this.category);
  final String name;
  final String category;
}

/// Concat's 21 built-in video effects, grouped into the categories CapCut
/// uses for its own effects browser. Apply logic is a later task — selecting
/// one here just confirms the pick (see [_EffectCard.onTap]).
const List<VideoEffect> kVideoEffects = [
  VideoEffect('Sharpen', 'Basic'),
  VideoEffect('Contrast', 'Basic'),
  VideoEffect('Gaussian Blur', 'Blur'),
  VideoEffect('Motion Blur', 'Blur'),
  VideoEffect('Zoom Blur', 'Blur'),
  VideoEffect('Color Wheels', 'Color'),
  VideoEffect('Curves', 'Color'),
  VideoEffect('Exposure', 'Color'),
  VideoEffect('Saturation', 'Color'),
  VideoEffect('White Balance', 'Color'),
  VideoEffect('Chroma Key', 'Cutout'),
  VideoEffect('Luma Key', 'Cutout'),
  VideoEffect('Chromatic Aberration', 'Distort'),
  VideoEffect('Fisheye', 'Distort'),
  VideoEffect('Pixelate', 'Distort'),
  VideoEffect('Bloom Pulse', 'Light'),
  VideoEffect('Glow', 'Light'),
  VideoEffect('Film Grain', 'Retro'),
  VideoEffect('Vignette', 'Retro'),
  VideoEffect('Halftone', 'Stylize'),
  VideoEffect('Posterize', 'Stylize'),
];

/// The category filter chips, in display order. "All" plus every category
/// that appears in [kVideoEffects].
const List<String> kEffectCategories = [
  'All',
  'Basic',
  'Blur',
  'Color',
  'Cutout',
  'Distort',
  'Light',
  'Retro',
  'Stylize',
];

/// The Effects tab: a searchable, category-filterable grid of Concat's
/// built-in video effects. Clicking a card is a stub for now — wiring an
/// effect onto the selected clip is a later task.
class EffectsPanel extends StatefulWidget {
  const EffectsPanel({super.key});

  @override
  State<EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends State<EffectsPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final effects = kVideoEffects.where((e) {
      final matchesCategory = _category == 'All' || e.category == _category;
      final matchesQuery =
          query.isEmpty || e.name.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: VTextField(
            controller: _searchController,
            hint: 'Search effects',
            icon: Icons.search,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: kEffectCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final category = kEffectCategories[i];
              return VChip(
                label: category,
                selected: category == _category,
                onTap: () => setState(() => _category = category),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: effects.isEmpty
              ? Center(
                  child: Text(
                    'No effects match "$_query".',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 520
                        ? 3
                        : constraints.maxWidth >= 320
                            ? 2
                            : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: effects.length,
                      itemBuilder: (context, i) => _EffectCard(
                        effect: effects[i],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EffectCard extends StatelessWidget {
  const _EffectCard({required this.effect});

  final VideoEffect effect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () => ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('${effect.name} — coming soon')),
        ),
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
              child: Center(
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            effect.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
