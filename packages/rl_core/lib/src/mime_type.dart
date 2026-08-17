/// File extension to MIME type lookup table and utilities.
///
/// NOTE: On the receiving side, any MIME type received over the wire is an
/// **untrusted display hint**. A remote peer can claim any MIME type for any
/// payload. The receiving side must NEVER use this field to choose how to open
/// a file, execute commands, or influence destination filesystem paths.
library;

/// The fallback MIME type when an extension is missing or unrecognized.
const String kDefaultMimeType = 'application/octet-stream';

/// Resolves a MIME type based on the file name's extension.
///
/// Returns [kDefaultMimeType] ('application/octet-stream') when the file name
/// has no extension or the extension is not in the recognized table.
/// This function never throws on malformed or adversarial file names.
String mimeTypeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) {
    return kDefaultMimeType;
  }
  final extension = fileName.substring(dot + 1).toLowerCase();
  return _extensionToMimeType[extension] ?? kDefaultMimeType;
}

const Map<String, String> _extensionToMimeType = <String, String>{
  // Images
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'svg': 'image/svg+xml',
  'bmp': 'image/bmp',
  'ico': 'image/x-icon',
  'tiff': 'image/tiff',
  'tif': 'image/tiff',
  'avif': 'image/avif',

  // Videos
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'avi': 'video/x-msvideo',
  'wmv': 'video/x-ms-wmv',
  '3gp': 'video/3gpp',
  '3g2': 'video/3gpp2',
  'ts': 'video/mp2t',
  'mts': 'video/mp2t',
  'm2ts': 'video/mp2t',
  'flv': 'video/x-flv',
  'ogv': 'video/ogg',

  // Audio
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/opus',
  'wma': 'audio/x-ms-wma',
  'aiff': 'audio/aiff',
  'aif': 'audio/aiff',
  'mid': 'audio/midi',
  'midi': 'audio/midi',

  // Documents
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'tsv': 'text/tab-separated-values',
  'rtf': 'application/rtf',
  'html': 'text/html',
  'htm': 'text/html',
  'json': 'application/json',
  'xml': 'application/xml',
  'yaml': 'text/yaml',
  'yml': 'text/yaml',
  'md': 'text/markdown',

  // Archives
  'zip': 'application/zip',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'tgz': 'application/gzip',
  'bz2': 'application/x-bzip2',
  'xz': 'application/x-xz',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
  'dmg': 'application/x-apple-diskimage',
  'iso': 'application/x-iso9660-image',
};
