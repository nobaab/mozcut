import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

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
/// (styled after CapCut's browser). Clicking a card is a "coming soon" stub —
/// this is catalogue UI only, it doesn't touch the Clip model or the render
/// engine.
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
                      itemBuilder: (context, i) =>
                          _TransitionCard(transition: results[i]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TransitionCard extends StatelessWidget {
  const _TransitionCard({required this.transition});
  final _Transition transition;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () => ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text('${transition.name} — coming soon'))),
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
                  transition.icon,
                  size: 26,
                  color: Colors.white.withValues(alpha: 0.5),
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
