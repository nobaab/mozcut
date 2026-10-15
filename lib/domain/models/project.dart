import 'clip.dart';
import 'sticker_overlay.dart';
import 'text_overlay.dart';

/// The output format of a project — the decisions the whole edit depends on.
class VideoSettings {
  const VideoSettings({
    this.width = 1920,
    this.height = 1080,
    this.fps = 30,
  });

  final int width;
  final int height;
  final double fps;

  /// "1920 × 1080 · 30 fps"
  String get label => '$width × $height · ${_trimFps(fps)} fps';

  static String _trimFps(double f) =>
      f == f.roundToDouble() ? f.toStringAsFixed(0) : f.toStringAsFixed(2);

  Map<String, dynamic> toJson() => {'width': width, 'height': height, 'fps': fps};

  factory VideoSettings.fromJson(Map<String, dynamic> j) => VideoSettings(
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        fps: (j['fps'] as num).toDouble(),
      );
}

/// A project: a folder on disk holding `mozcut.json`, plus the edit it
/// describes. Mirrors Concat's model — a project is a real thing from the
/// moment it is created, not a promise to save later.
class Project {
  Project({
    required this.folderPath,
    required this.name,
    this.video = const VideoSettings(),
    List<Clip>? clips,
    List<TextOverlay>? textOverlays,
    List<StickerOverlay>? stickerOverlays,
    int? createdAt,
    int? modifiedAt,
  })  : clips = clips ?? [],
        textOverlays = textOverlays ?? [],
        stickerOverlays = stickerOverlays ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        modifiedAt = modifiedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// The project folder — the project's identity.
  final String folderPath;
  String name;
  VideoSettings video;
  List<Clip> clips;

  /// Text/title overlays, timed on the final concatenated timeline. See
  /// [TextOverlay] for why these live at the project level rather than on a
  /// clip.
  List<TextOverlay> textOverlays;

  /// Emoji sticker overlays, timed on the final concatenated timeline. See
  /// [StickerOverlay] for why these live at the project level rather than on
  /// a clip — same reasoning as [textOverlays].
  List<StickerOverlay> stickerOverlays;
  final int createdAt;
  int modifiedAt;

  static const manifestName = 'mozcut.json';
  static const formatVersion = '0.2.0';

  Map<String, dynamic> toManifest() => {
        'mozcut': formatVersion,
        'name': name,
        'video': video.toJson(),
        'clips': clips.map((c) => c.toJson()).toList(),
        'textOverlays': textOverlays.map((t) => t.toJson()).toList(),
        'stickerOverlays': stickerOverlays.map((s) => s.toJson()).toList(),
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
      };

  factory Project.fromManifest(String folderPath, Map<String, dynamic> j) =>
      Project(
        folderPath: folderPath,
        name: j['name'] as String? ?? 'Untitled',
        video: j['video'] != null
            ? VideoSettings.fromJson(j['video'] as Map<String, dynamic>)
            : const VideoSettings(),
        clips: (j['clips'] as List? ?? [])
            .map((e) => Clip.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Absent in manifests written before this feature existed — defaults
        // to an empty list, so opening an old project is unaffected.
        textOverlays: (j['textOverlays'] as List? ?? [])
            .map((e) => TextOverlay.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Absent in manifests written before this feature existed — defaults
        // to an empty list, so opening an old project is unaffected.
        stickerOverlays: (j['stickerOverlays'] as List? ?? [])
            .map((e) => StickerOverlay.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: (j['createdAt'] as num?)?.toInt(),
        modifiedAt: (j['modifiedAt'] as num?)?.toInt(),
      );
}

/// A row in the recents list — enough to show a card and reopen the project.
/// Stored in the app's config dir, never inside a project folder.
class RecentProject {
  const RecentProject({
    required this.path,
    required this.name,
    required this.video,
    required this.openedAt,
    this.posterPath,
  });

  final String path;
  final String name;
  final VideoSettings video;
  final int openedAt;

  /// A JPEG frame from the first clip, if one has been produced.
  final String? posterPath;

  /// "yesterday", "4 days ago", "just now"
  String get when {
    final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(openedAt));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return '${(diff.inDays / 30).floor()} mo ago';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'video': video.toJson(),
        'openedAt': openedAt,
        'posterPath': posterPath,
      };

  factory RecentProject.fromJson(Map<String, dynamic> j) => RecentProject(
        path: j['path'] as String,
        name: j['name'] as String,
        video: VideoSettings.fromJson(j['video'] as Map<String, dynamic>),
        openedAt: (j['openedAt'] as num).toInt(),
        posterPath: j['posterPath'] as String?,
      );
}
