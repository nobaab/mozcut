import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Aliased: this file also uses Flutter's own `Clip` widget behavior enum, so
// the domain model needs a distinct name to avoid colliding with it.
import '../../../../domain/models/clip.dart' as domain show Clip;
import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../view_models/editor_view_model.dart';

/// A single entry in the effects catalogue: a name and the category it's
/// filed under (matching Concat's built-in video-effect categories, see
/// docs/FEATURES.md Appendix).
class VideoEffect {
  const VideoEffect(this.name, this.category);
  final String name;
  final String category;
}

/// Concat's 21 built-in video effects, grouped into the categories CapCut
/// uses for its own effects browser. Tapping one in [EffectsPanel] sets
/// [domain.Clip.effectId] on the selected clip, which
/// `lib/domain/models/effect_presets.dart` maps to a concrete ffmpeg filter
/// applied on export (see `FfmpegEngine._videoFilterChain`).
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
/// built-in video effects. Tapping a card applies (or, tapping the
/// already-applied one again, clears) that effect on the selected clip's
/// [domain.Clip.effectId] — see `effect_presets.dart` for the name -> ffmpeg
/// mapping actually used on export. Same interaction shape as the Filters
/// tab (`filters_panel.dart`).
class EffectsPanel extends ConsumerStatefulWidget {
  const EffectsPanel({super.key});

  @override
  ConsumerState<EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends ConsumerState<EffectsPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyEffect(domain.Clip? clip, VideoEffect effect) {
    if (clip == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Select a clip first')));
      return;
    }
    final editor = ref.read(editorProvider.notifier);
    editor.setSelectedEffect(clip.effectId == effect.name ? null : effect.name);
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
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
        if (clip?.effectId != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Effect: ${clip!.effectId}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7))),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(editorProvider.notifier).setSelectedEffect(null),
                  child: const Text('None'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                Text('Intensity',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55))),
                Expanded(
                  child: Slider(
                    value: clip.effectIntensity.clamp(0.0, 1.0),
                    onChanged: (v) => ref
                        .read(editorProvider.notifier)
                        .setSelectedEffectIntensity(v),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                      '${(clip.effectIntensity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
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
                        selected: effects[i].name == clip?.effectId,
                        onTap: () => _applyEffect(clip, effects[i]),
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
  const _EffectCard({
    required this.effect,
    required this.selected,
    required this.onTap,
  });

  final VideoEffect effect;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.well,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.line,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 22,
                  color: selected
                      ? AppColors.accent
                      : Colors.white.withValues(alpha: 0.4),
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
