import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('mimeTypeForFileName', () {
    test('resolves common image formats', () {
      expect(mimeTypeForFileName('photo.jpg'), 'image/jpeg');
      expect(mimeTypeForFileName('photo.jpeg'), 'image/jpeg');
      expect(mimeTypeForFileName('graphic.png'), 'image/png');
      expect(mimeTypeForFileName('animation.gif'), 'image/gif');
      expect(mimeTypeForFileName('picture.webp'), 'image/webp');
      expect(mimeTypeForFileName('IMG_4021.heic'), 'image/heic');
      expect(mimeTypeForFileName('IMG_4022.HEIF'), 'image/heif');
      expect(mimeTypeForFileName('vector.svg'), 'image/svg+xml');
      expect(mimeTypeForFileName('bitmap.bmp'), 'image/bmp');
      expect(mimeTypeForFileName('favicon.ico'), 'image/x-icon');
      expect(mimeTypeForFileName('scan.tiff'), 'image/tiff');
      expect(mimeTypeForFileName('scan.tif'), 'image/tiff');
      expect(mimeTypeForFileName('modern.avif'), 'image/avif');
    });

    test('resolves common video formats', () {
      expect(mimeTypeForFileName('clip.mp4'), 'video/mp4');
      expect(mimeTypeForFileName('recording.mov'), 'video/quicktime');
      expect(mimeTypeForFileName('movie.mkv'), 'video/x-matroska');
      expect(mimeTypeForFileName('stream.webm'), 'video/webm');
      expect(mimeTypeForFileName('video.avi'), 'video/x-msvideo');
      expect(mimeTypeForFileName('video.wmv'), 'video/x-ms-wmv');
      expect(mimeTypeForFileName('video.m4v'), 'video/x-m4v');
      expect(mimeTypeForFileName('mobile.3gp'), 'video/3gpp');
      expect(mimeTypeForFileName('stream.ts'), 'video/mp2t');
    });

    test('resolves common audio formats', () {
      expect(mimeTypeForFileName('song.mp3'), 'audio/mpeg');
      expect(mimeTypeForFileName('track.m4a'), 'audio/mp4');
      expect(mimeTypeForFileName('audio.aac'), 'audio/aac');
      expect(mimeTypeForFileName('sample.wav'), 'audio/wav');
      expect(mimeTypeForFileName('lossless.flac'), 'audio/flac');
      expect(mimeTypeForFileName('audio.ogg'), 'audio/ogg');
      expect(mimeTypeForFileName('voice.opus'), 'audio/opus');
    });

    test('resolves common document formats', () {
      expect(mimeTypeForFileName('report.pdf'), 'application/pdf');
      expect(mimeTypeForFileName('document.doc'), 'application/msword');
      expect(
        mimeTypeForFileName('document.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(
        mimeTypeForFileName('sheet.xls'),
        'application/vnd.ms-excel',
      );
      expect(
        mimeTypeForFileName('sheet.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        mimeTypeForFileName('slides.ppt'),
        'application/vnd.ms-powerpoint',
      );
      expect(
        mimeTypeForFileName('slides.pptx'),
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
      expect(mimeTypeForFileName('notes.txt'), 'text/plain');
      expect(mimeTypeForFileName('data.csv'), 'text/csv');
      expect(mimeTypeForFileName('page.html'), 'text/html');
      expect(mimeTypeForFileName('config.json'), 'application/json');
      expect(mimeTypeForFileName('markup.xml'), 'application/xml');
      expect(mimeTypeForFileName('README.md'), 'text/markdown');
    });

    test('resolves common archive formats', () {
      expect(mimeTypeForFileName('bundle.zip'), 'application/zip');
      expect(mimeTypeForFileName('archive.tar'), 'application/x-tar');
      expect(mimeTypeForFileName('compressed.gz'), 'application/gzip');
      expect(mimeTypeForFileName('archive.tar.gz'), 'application/gzip');
      expect(mimeTypeForFileName('package.7z'), 'application/x-7z-compressed');
      expect(mimeTypeForFileName('installer.dmg'),
          'application/x-apple-diskimage');
    });

    test('is case-insensitive', () {
      expect(mimeTypeForFileName('CLIP.MP4'), 'video/mp4');
      expect(mimeTypeForFileName('Photo.JpG'), 'image/jpeg');
      expect(mimeTypeForFileName('Doc.PDF'), 'application/pdf');
    });

    test('falls back to application/octet-stream for unknown extensions', () {
      expect(mimeTypeForFileName('unknown.xyz'), 'application/octet-stream');
      expect(mimeTypeForFileName('binary.dat'), 'application/octet-stream');
      expect(mimeTypeForFileName('custom.myext'), 'application/octet-stream');
    });

    test(
        'falls back to application/octet-stream for missing or malformed names',
        () {
      expect(mimeTypeForFileName(''), 'application/octet-stream');
      expect(mimeTypeForFileName('no_extension'), 'application/octet-stream');
      expect(mimeTypeForFileName('trailing_dot.'), 'application/octet-stream');
      expect(mimeTypeForFileName('.hidden'), 'application/octet-stream');
    });

    test('handles path strings and adversarial input without throwing', () {
      expect(
        mimeTypeForFileName('/var/mobile/Containers/IMG_0001.MOV'),
        'video/quicktime',
      );
      expect(
        mimeTypeForFileName('../../etc/passwd'),
        'application/octet-stream',
      );
      expect(
        mimeTypeForFileName('..\\..\\malicious.exe.mp4'),
        'video/mp4',
      );
      expect(
        mimeTypeForFileName('evil.exe'),
        'application/octet-stream',
      );
    });
  });
}
