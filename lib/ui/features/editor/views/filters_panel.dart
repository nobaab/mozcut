import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/app_spacing.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/fields.dart';

/// One entry in the filter catalogue: a named preset grouped under a category,
/// mirroring Concat's 57 built-in filters (see docs/FEATURES.md Appendix).
class FilterPreset {
  const FilterPreset(this.name, this.category);
  final String name;
  final String category;
}

/// Category order used both for the chip row and for grouping the grid.
/// "Adjust" has no chip of its own (it's a single catch-all preset) but still
/// shows up as its own section when "All" is selected.
const _kFilterCategories = <String>[
  'Cinematic',
  'Everyday',
  'Color',
  'B&W',
  'Film',
  'Retro',
  'Portrait',
  'Scenery',
  'Stylised',
  'Vibe',
  'Food',
  'Adjust',
];

/// The chips shown above the grid. "All" plus every named category.
const _kFilterChips = <String>['All', ..._kFilterCategories];

/// Concat's full 57-filter catalogue (docs/FEATURES.md Appendix), used as the
/// target list for Vidkaat's own filter browser.
const _kFilters = <FilterPreset>[
  // Cinematic (13)
  FilterPreset('Bleach Bypass', 'Cinematic'),
  FilterPreset('Cool Blue', 'Cinematic'),
  FilterPreset('Cyberpunk', 'Cinematic'),
  FilterPreset('Daydream', 'Cinematic'),
  FilterPreset('Film', 'Cinematic'),
  FilterPreset('Midnight', 'Cinematic'),
  FilterPreset('Moody', 'Cinematic'),
  FilterPreset('Night', 'Cinematic'),
  FilterPreset('Noir', 'Cinematic'),
  FilterPreset('Rain', 'Cinematic'),
  FilterPreset('Sage', 'Cinematic'),
  FilterPreset('Sci-Fi', 'Cinematic'),
  FilterPreset('Teal & Orange', 'Cinematic'),
  // Everyday (10)
  FilterPreset('Clean', 'Everyday'),
  FilterPreset('Cloudless Sky', 'Everyday'),
  FilterPreset('Fresh', 'Everyday'),
  FilterPreset('Golden Hour', 'Everyday'),
  FilterPreset('Ivory', 'Everyday'),
  FilterPreset('Lagoon', 'Everyday'),
  FilterPreset('Milk', 'Everyday'),
  FilterPreset('Soft Light', 'Everyday'),
  FilterPreset('Umber', 'Everyday'),
  FilterPreset('Vivid', 'Everyday'),
  // Color (4)
  FilterPreset('Contrast Pop', 'Color'),
  FilterPreset('Cool', 'Color'),
  FilterPreset('Vibrance', 'Color'),
  FilterPreset('Warm', 'Color'),
  // B&W (2)
  FilterPreset('High-Contrast Mono', 'B&W'),
  FilterPreset('Silver', 'B&W'),
  // Film (3)
  FilterPreset('Classic Chrome', 'Film'),
  FilterPreset('Retro 70s', 'Film'),
  FilterPreset('Super 8', 'Film'),
  // Retro (7)
  FilterPreset('Bronze', 'Retro'),
  FilterPreset('Digicam', 'Retro'),
  FilterPreset('Falling Dust', 'Retro'),
  FilterPreset('Mono', 'Retro'),
  FilterPreset('Polaroid', 'Retro'),
  FilterPreset('VHS', 'Retro'),
  FilterPreset('Vintage', 'Retro'),
  // Portrait (4)
  FilterPreset('Fair', 'Portrait'),
  FilterPreset('Natural', 'Portrait'),
  FilterPreset('Peach', 'Portrait'),
  FilterPreset('Rosy', 'Portrait'),
  // Scenery (4)
  FilterPreset('Autumn', 'Scenery'),
  FilterPreset('Tropical', 'Scenery'),
  FilterPreset('Vivid Landscape', 'Scenery'),
  FilterPreset('Winter Cool', 'Scenery'),
  // Stylised (6)
  FilterPreset('Marquee', 'Stylised'),
  FilterPreset('Matcha', 'Stylised'),
  FilterPreset('Neon', 'Stylised'),
  FilterPreset('Pink Fuzz', 'Stylised'),
  FilterPreset('Retro Cartoon', 'Stylised'),
  FilterPreset('Spooky', 'Stylised'),
  // Vibe (2)
  FilterPreset('Dreamy', 'Vibe'),
  FilterPreset('Vaporwave', 'Vibe'),
  // Food (1)
  FilterPreset('Delicious', 'Food'),
  // Adjust (1)
  FilterPreset('Adjust', 'Adjust'),
];

/// The Filters tab: search + category chips over a grid of filter preset
/// cards, sourced from Concat's 57-filter catalogue. Purely a browsing
/// catalogue for now — applying a filter is not yet wired to the clip model
/// or render engine.
class FiltersPanel extends StatefulWidget {
  const FiltersPanel({super.key});

  @override
  State<FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<FiltersPanel> {
  final _searchController = TextEditingController();
  String _search = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FilterPreset> get _matches {
    final q = _search.trim().toLowerCase();
    return _kFilters.where((f) {
      final matchesCategory = _category == 'All' || f.category == _category;
      final matchesSearch = q.isEmpty || f.name.toLowerCase().contains(q);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final sections = <String, List<FilterPreset>>{};
    for (final cat in _kFilterCategories) {
      final items = matches.where((f) => f.category == cat).toList();
      if (items.isNotEmpty) sections[cat] = items;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: VTextField(
            controller: _searchController,
            hint: 'Search filters',
            icon: Icons.search,
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        SizedBox(
          height: AppSpacing.controlHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            scrollDirection: Axis.horizontal,
            itemCount: _kFilterChips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final chip = _kFilterChips[i];
              return VChip(
                label: chip,
                selected: _category == chip,
                onTap: () => setState(() => _category = chip),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: sections.isEmpty
              ? Center(
                  child: Text(
                    'No filters found.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final entry in sections.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      _FilterGrid(filters: entry.value),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterGrid extends StatelessWidget {
  const _FilterGrid({required this.filters});

  final List<FilterPreset> filters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 110).floor().clamp(2, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.92,
          ),
          itemCount: filters.length,
          itemBuilder: (context, i) => _FilterCard(filter: filters[i]),
        );
      },
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.filter});

  final FilterPreset filter;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(filter.category);
    return Material(
      color: AppColors.well,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('${filter.name} — coming soon'))),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.28),
                      AppColors.well,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(Icons.filter_vintage_outlined,
                      size: 22, color: accent.withValues(alpha: 0.85)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  child: Text(
                    filter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _categoryColor(String category) {
    switch (category) {
      case 'Cinematic':
        return const Color(0xFF6C7BFF);
      case 'Everyday':
        return const Color(0xFFFFC266);
      case 'Color':
        return const Color(0xFFFF6B6B);
      case 'B&W':
        return const Color(0xFFB0B0B0);
      case 'Film':
        return const Color(0xFFD9A066);
      case 'Retro':
        return const Color(0xFFE07A9E);
      case 'Portrait':
        return const Color(0xFFFFA3B5);
      case 'Scenery':
        return const Color(0xFF66D9A0);
      case 'Stylised':
        return const Color(0xFFB266FF);
      case 'Vibe':
        return const Color(0xFF66D9E0);
      case 'Food':
        return const Color(0xFFFFB366);
      case 'Adjust':
        return AppColors.accent;
      default:
        return AppColors.accent;
    }
  }
}
