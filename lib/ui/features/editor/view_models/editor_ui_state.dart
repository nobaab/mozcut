import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_ui_state.g.dart';

/// The left-hand browser tabs, matching CapCut's feature rail. Sub-content for
/// most of these is still to come; the tabs themselves all exist now.
enum EditorLeftTab {
  media('Import', Icons.video_library_outlined),
  audio('Audio', Icons.music_note_outlined),
  text('Text', Icons.title),
  stickers('Stickers', Icons.emoji_emotions_outlined),
  overlay('Overlay', Icons.picture_in_picture_alt_outlined),
  effects('Effects', Icons.auto_awesome_outlined),
  transitions('Transitions', Icons.swap_horiz),
  captions('Captions', Icons.closed_caption_outlined),
  filters('Filters', Icons.filter_vintage_outlined),
  templates('Templates', Icons.dashboard_outlined);

  const EditorLeftTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

@Riverpod(keepAlive: true)
class LeftTab extends _$LeftTab {
  @override
  EditorLeftTab build() => EditorLeftTab.media;
  void set(EditorLeftTab tab) => state = tab;
}

/// The right-hand inspector tabs.
enum EditorRightTab {
  video('Video'),
  audio('Audio'),
  speed('Speed'),
  animation('Animation'),
  adjustment('Adjustment');

  const EditorRightTab(this.label);
  final String label;
}

@Riverpod(keepAlive: true)
class RightTab extends _$RightTab {
  @override
  EditorRightTab build() => EditorRightTab.video;
  void set(EditorRightTab tab) => state = tab;
}

/// The Video tab's sub-tabs.
enum VideoSubTab {
  basic('Basic'),
  removeBg('Remove BG'),
  mask('Mask'),
  retouch('Retouch');

  const VideoSubTab(this.label);
  final String label;
}

@Riverpod(keepAlive: true)
class VideoSub extends _$VideoSub {
  @override
  VideoSubTab build() => VideoSubTab.basic;
  void set(VideoSubTab tab) => state = tab;
}

/// Timeline zoom, in pixels per second.
@Riverpod(keepAlive: true)
class TimelineZoom extends _$TimelineZoom {
  @override
  double build() => 40;
  void set(double pxPerSecond) => state = pxPerSecond.clamp(6, 240);
  void zoomIn() => set(state * 1.3);
  void zoomOut() => set(state / 1.3);
}

/// Whether dragging/trimming a clip magnetizes to nearby snap targets (`0`,
/// the playhead, other clips'/audio-clips'/overlays' edges — see
/// `lib/ui/features/editor/timeline_snap.dart`). Defaults on, matching both
/// CapCut-style reference editors (docs/TIMELINE-BEHAVIOR.md §7). Toggled by
/// the timeline toolbar's snap button and the `n` keyboard shortcut.
@Riverpod(keepAlive: true)
class SnapEnabled extends _$SnapEnabled {
  @override
  bool build() => true;
  void set(bool value) => state = value;
  void toggle() => state = !state;
}

/// The timeline position (timeline seconds) the active drag/trim is currently
/// snapped to, or null when nothing is snapped. Written by the per-clip
/// move/trim handlers in `timeline_panel.dart` while a gesture is in
/// progress; read only by the isolated snap-line widget there, the same
/// "watch just this, not the whole timeline" treatment `Playhead`/`_Playhead`
/// get — so the magnetic line can appear/disappear every drag frame without
/// rebuilding every clip bar, filmstrip and waveform.
@Riverpod(keepAlive: true)
class SnapIndicator extends _$SnapIndicator {
  @override
  double? build() => null;
  void set(double? timelineSeconds) => state = timelineSeconds;
}

/// Whether the preview is currently playing. Written by [PlayerPanel] from
/// its media_kit player's `playing` stream; read by the timeline to drive
/// auto-scroll-follow during playback (keeping the playhead on-screen — see
/// `_TimelinePanelState._followPlayhead` in `timeline_panel.dart`) without
/// the timeline needing any direct reference to the player.
@Riverpod(keepAlive: true)
class IsPlaying extends _$IsPlaying {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// The draggable panel sizes: left browser width, right inspector width, and
/// timeline height (all in logical pixels).
class PanelSizes {
  const PanelSizes(
      {required this.left, required this.right, required this.timeline});
  final double left;
  final double right;
  final double timeline;

  PanelSizes copyWith({double? left, double? right, double? timeline}) =>
      PanelSizes(
        left: left ?? this.left,
        right: right ?? this.right,
        timeline: timeline ?? this.timeline,
      );
}

@Riverpod(keepAlive: true)
class Panels extends _$Panels {
  @override
  PanelSizes build() =>
      const PanelSizes(left: 380, right: 300, timeline: 220);

  /// Drag the divider on the right edge of the left panel.
  void dragLeft(double dx) =>
      state = state.copyWith(left: (state.left + dx).clamp(260, 620));

  /// Drag the divider on the left edge of the right panel (dragging left grows
  /// the inspector).
  void dragRight(double dx) =>
      state = state.copyWith(right: (state.right - dx).clamp(240, 560));

  /// Drag the divider above the timeline (dragging up grows the timeline).
  void dragTimeline(double dy) =>
      state = state.copyWith(timeline: (state.timeline - dy).clamp(140, 560));
}
