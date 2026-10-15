import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Aliased: this file also uses Flutter's own `Clip` enum (clipBehavior), so
// the domain model needs a distinct name to avoid colliding with it.
import '../../../../domain/models/clip.dart' as domain show Clip;
import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';
import '../view_models/editor_view_model.dart';

/// A transition in the catalogue. Purely descriptive — no engine wiring yet.
class _Transition {
  const _Transition(this.name, this.category, this.icon);
  final String name;
  final String category;
  final IconData icon;
}

/// Concat's 20 built-in transitions (see docs/FEATURES.md Appendix), grouped
/// into the categories shown as filter chips.
const _transitions = <_Transition>[
  _Transition('Dissolve', 'Dissolve', Icons.blur_on),
  _Transition('Blur Dissolve', 'Dissolve', Icons.blur_circular),
  _Transition('Film Burn', 'Light', Icons.local_fire_department_outlined),
  _Transition('Glitch', 'Glitch', Icons.broken_image_outlined),
  _Transition('Glitch Warp', 'Glitch', Icons.waves),
  _Transition('RGB Split', 'Glitch', Icons.filter_3),
  _Transition('Cube', 'Spin', Icons.view_in_ar_outlined),
  _Transition('Light Leak', 'Light', Icons.wb_sunny_outlined),
  _Transition('Light Leak Flash', 'Light', Icons.flash_on_outlined),
  _Transition('Push', 'Slide', Icons.arrow_forward),
  _Transition('Slide', 'Slide', Icons.swap_horiz),
  _Transition('Spin', 'Spin', Icons.rotate_right),
  _Transition('Swirl', 'Spin', Icons.cyclone_outlined),
  _Transition('Clock Wipe', 'Wipe', Icons.access_time),
  _Transition('Iris', 'Wipe', Icons.vignette_outlined),
  _Transition('Linear Wipe', 'Wipe', Icons.horizontal_split),
  _Transition('Shape Wipe', 'Wipe', Icons.category_outlined),
  _Transition('Whip Pan', 'Slide', Icons.fast_forward_outlined),
  _Transition('Zoom', 'Zoom', Icons.zoom_in),
  _Transition('Zoom Blur', 'Zoom', Icons.zoom_out_map),
];

/// The full catalogue, exposed read-only for tests that check every entry
/// has a matching `kTransitionPresets` (ffmpeg `xfade`) mapping — see
/// test/transition_presets_test.dart.
List<String> get kTransitionCatalogue =>
    List.unmodifiable(_transitions.map((t) => t.name));

const _categories = <String>[
  'All',
  'Basic',
  'Dissolve',
  'Glitch',
  'Light',
  'Slide',
  'Spin',
  'Wipe',
  'Zoom',
];

/// The Transitions tab: a searchable, filterable catalogue of transitions
/// (styled after CapCut's browser). Tapping a card sets (or, tapping the
/// already-applied one again, clears) that transition on the SELECTED clip's
/// `Clip.transitionId` — it plays entering the selected clip from the
/// previous one. See `lib/domain/models/transition_presets.dart` for the
/// name -> ffmpeg `xfade` mapping actually used on export.
class TransitionsPanel extends ConsumerStatefulWidget {
  const TransitionsPanel({super.key});

  @override
  ConsumerState<TransitionsPanel> createState() => _TransitionsPanelState();
}

class _TransitionsPanelState extends ConsumerState<TransitionsPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyTransition(domain.Clip? clip, _Transition transition) {
    if (clip == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            const SnackBar(content: Text('Select a clip first')));
      return;
    }
    final editor = ref.read(editorProvider.notifier);
    editor.setSelectedTransition(
        clip.transitionId == transition.name ? null : transition.name);
  }

  List<_Transition> get _filtered {
    return _transitions.where((t) {
      final matchesCategory = _category == 'All' ||
          (_category == 'Basic' && t.category == 'Dissolve') ||
          t.category == _category;
      final matchesQuery =
          _query.isEmpty || t.name.toLowerCase().contains(_query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(editorProvider.select((s) => s.selected));
    final results = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: VTextField(
            controller: _searchController,
            hint: 'Search transitions',
            icon: Icons.search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        if (clip != null && clip.transitionId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Transition: ${clip.transitionId}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7))),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(editorProvider.notifier)
                          .setSelectedTransition(null),
                      child: const Text('None'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('Duration',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.55))),
                    Expanded(
                      child: Slider(
                        value: clip.transitionDuration.clamp(0.05, 5.0),
                        min: 0.05,
                        max: 5.0,
                        onChanged: (v) => ref
                            .read(editorProvider.notifier)
                            .setSelectedTransition(clip.transitionId,
                                duration: v),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                          '${clip.transitionDuration.toStringAsFixed(1)}s',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final category = _categories[i];
              return VChip(
                label: category,
                selected: _category == category,
                onTap: () => setState(() => _category = category),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    'No transitions match "${_searchController.text}".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        (constraints.maxWidth / 140).floor().clamp(2, 6);
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.92,
                      ),
                      itemCount: results.length,
                      itemBuilder: (context, i) => _TransitionCard(
                        transition: results[i],
                        selected: clip?.transitionId == results[i].name,
                        onTap: () => _applyTransition(clip, results[i]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TransitionCard extends StatelessWidget {
  const _TransitionCard({
    required this.transition,
    required this.selected,
    required this.onTap,
  });
  final _Transition transition;
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
                  selected ? Icons.check_circle : transition.icon,
                  size: 26,
                  color: selected
                      ? AppColors.accent
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            transition.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
