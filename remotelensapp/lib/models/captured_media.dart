enum MediaType { image, video }

class CapturedMedia {
  final String path;
  final MediaType type;
  final String? thumbnailPath;

  const CapturedMedia({
    required this.path,
    required this.type,
    this.thumbnailPath,
  });
}
