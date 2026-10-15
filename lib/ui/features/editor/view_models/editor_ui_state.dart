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
