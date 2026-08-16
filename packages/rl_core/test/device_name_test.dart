import 'package:test/test.dart';
import 'package:rl_core/rl_core.dart';

void main() {
  group('sanitiseDeviceName', () {
    group('valid names', () {
      test('accepts normal alphanumeric names', () {
        expect(
            sanitiseDeviceName("Ahmed's MacBook Pro"), "Ahmed's MacBook Pro");
        expect(sanitiseDeviceName('Living Room PC'), 'Living Room PC');
        expect(sanitiseDeviceName('iPhone 15'), 'iPhone 15');
        expect(sanitiseDeviceName('Pixel-9_Pro'), 'Pixel-9_Pro');
      });

      test('trims leading and trailing whitespace', () {
        expect(sanitiseDeviceName('   Work Laptop   '), 'Work Laptop');
        expect(sanitiseDeviceName('  Mac Mini  '), 'Mac Mini');
      });

      test('accepts international characters and non-Latin scripts', () {
        expect(sanitiseDeviceName('München Desktop'), 'München Desktop');
        expect(sanitiseDeviceName('Élise Laptop'), 'Élise Laptop');
        expect(sanitiseDeviceName('한국어 맥북'), '한국어 맥북');
        expect(sanitiseDeviceName('日本語 PC'), '日本語 PC');
        expect(sanitiseDeviceName('компьютер'), 'компьютер');
        expect(sanitiseDeviceName('حاسوب أحمد'), 'حاسوب أحمد');
      });

      test('accepts emojis and symbols', () {
        expect(sanitiseDeviceName('🎮 Gaming Rig'), '🎮 Gaming Rig');
        expect(sanitiseDeviceName('🚀 Workstation 💻'), '🚀 Workstation 💻');
      });

      test('accepts exactly 64 ASCII characters', () {
        final name64 = 'A' * 64;
        expect(sanitiseDeviceName(name64), name64);
      });

      test('accepts exactly 64 user-perceived emoji characters', () {
        // Each emoji is multiple code units but exactly 1 user-perceived character
        final name64 = '🎮' * 64;
        expect(sanitiseDeviceName(name64), name64);
      });

      test('accepts 64 complex multi-codepoint grapheme clusters', () {
        // Flag emoji (2 code points per flag)
        final flags64 = '🇺🇸' * 64;
        expect(sanitiseDeviceName(flags64), flags64);

        // Skin-tone emoji (2 code points per emoji)
        final thumbs64 = '👍🏽' * 64;
        expect(sanitiseDeviceName(thumbs64), thumbs64);
      });
    });

    group('Unicode NFC normalization', () {
      test('normalises decomposed Latin characters to NFC precomposed forms',
          () {
        // 'e' + combining acute (U+0301) -> 'é' (U+00E9)
        const decomposed = 'e\u0301lise';
        const nfcExpected = 'élise';
        expect(decomposed.length, 6);
        expect(nfcExpected.length, 5);

        final result = sanitiseDeviceName(decomposed);
        expect(result, nfcExpected);
        expect(result!.codeUnits,
            const <int>[0x00E9, 0x006C, 0x0069, 0x0073, 0x0065]);
      });

      test('normalises A + combining ring to Å (U+00C5)', () {
        const decomposed = 'A\u030A';
        final result = sanitiseDeviceName(decomposed);
        expect(result, 'Å');
        expect(result!.codeUnits, const <int>[0x00C5]);
      });

      test('normalises a + combining diaeresis to ä (U+00E4)', () {
        const decomposed = 'a\u0308';
        final result = sanitiseDeviceName(decomposed);
        expect(result, 'ä');
        expect(result!.codeUnits, const <int>[0x00E4]);
      });

      test('normalises c + combining cedilla to ç (U+00E7)', () {
        const decomposed = 'c\u0327';
        final result = sanitiseDeviceName(decomposed);
        expect(result, 'ç');
        expect(result!.codeUnits, const <int>[0x00E7]);
      });

      test('normalises n + combining tilde to ñ (U+00F1)', () {
        const decomposed = 'n\u0303';
        final result = sanitiseDeviceName(decomposed);
        expect(result, 'ñ');
        expect(result!.codeUnits, const <int>[0x00F1]);
      });

      test('normalises Hangul Conjoining Jamo to Hangul Syllables', () {
        // U+1100 (Choseong Kiyeok) + U+1161 (Jungseong A) -> U+AC00 (가)
        const decomposed = '\u1100\u1161';
        final result = sanitiseDeviceName(decomposed);
        expect(result, '가');
        expect(result!.codeUnits, const <int>[0xAC00]);
      });
    });

    group('rejections: empty and whitespace-only', () {
      test('rejects null and empty string', () {
        expect(sanitiseDeviceName(null), isNull);
        expect(sanitiseDeviceName(''), isNull);
      });

      test('rejects strings that are only ASCII whitespace', () {
        expect(sanitiseDeviceName(' '), isNull);
        expect(sanitiseDeviceName('     '), isNull);
        expect(sanitiseDeviceName('\t'), isNull);
        expect(sanitiseDeviceName('\n'), isNull);
        expect(sanitiseDeviceName('\r\n'), isNull);
      });

      test('rejects strings that are only Unicode whitespace', () {
        expect(sanitiseDeviceName('\u00A0'), isNull); // NBSP
        expect(sanitiseDeviceName('\u2000\u2001\u2002\u2003'),
            isNull); // En/Em quads
        expect(sanitiseDeviceName('\u3000'), isNull); // Ideographic space
        expect(sanitiseDeviceName('  \u00A0  \u3000  '), isNull);
      });
    });

    group('rejections: zero-width, invisible, and format-only characters', () {
      test('rejects zero-width space (U+200B)', () {
        expect(sanitiseDeviceName('\u200B'), isNull);
        expect(sanitiseDeviceName('\u200B\u200B\u200B'), isNull);
        expect(sanitiseDeviceName('  \u200B  '), isNull);
        expect(sanitiseDeviceName('Device\u200BName'), isNull);
      });

      test('rejects BOM / zero-width non-breaking space (U+FEFF)', () {
        expect(sanitiseDeviceName('\uFEFF'), isNull);
        expect(sanitiseDeviceName('  \uFEFF  '), isNull);
        expect(sanitiseDeviceName('\uFEFFDevice'), isNull);
      });

      test('rejects standalone zero-width joiner/non-joiner', () {
        expect(sanitiseDeviceName('\u200C'), isNull);
        expect(sanitiseDeviceName('\u200D'), isNull);
        expect(sanitiseDeviceName('  \u200C  \u200D  '), isNull);
      });

      test('rejects Braille pattern blank (U+2800)', () {
        expect(sanitiseDeviceName('\u2800'), isNull);
        expect(sanitiseDeviceName('  \u2800  '), isNull);
        expect(sanitiseDeviceName('Device\u2800Name'), isNull);
      });

      test('rejects soft hyphen (U+00AD)', () {
        expect(sanitiseDeviceName('\u00AD'), isNull);
        expect(sanitiseDeviceName('Device\u00ADName'), isNull);
      });

      test('rejects word joiner and invisible operators', () {
        expect(sanitiseDeviceName('\u2060'), isNull);
        expect(sanitiseDeviceName('\u2061'), isNull);
        expect(sanitiseDeviceName('\u2062'), isNull);
        expect(sanitiseDeviceName('\u2063'), isNull);
        expect(sanitiseDeviceName('\u2064'), isNull);
      });

      test('rejects bidi overrides and isolates', () {
        expect(sanitiseDeviceName('\u202A\u202C'), isNull);
        expect(sanitiseDeviceName('\u202E'), isNull); // RLO
        expect(sanitiseDeviceName('Device\u202EName'), isNull);
        expect(sanitiseDeviceName('\u2066\u2069'), isNull);
      });

      test('rejects Unicode tag characters', () {
        expect(sanitiseDeviceName('\u{E0001}'), isNull);
        expect(sanitiseDeviceName('Device\u{E0020}Name'), isNull);
      });

      test('rejects mixed whitespace and invisible characters', () {
        expect(sanitiseDeviceName('  \u200B  \uFEFF  \u2800  '), isNull);
      });
    });

    group('rejections: control characters and ANSI escape sequences', () {
      test('rejects C0 control characters (0x00 - 0x1F)', () {
        expect(sanitiseDeviceName('\x00'), isNull); // NUL
        expect(sanitiseDeviceName('Device\x00Name'), isNull);
        expect(sanitiseDeviceName('Device\x07Name'), isNull); // BEL
        expect(sanitiseDeviceName('Device\x08Name'), isNull); // BS
        expect(sanitiseDeviceName('Device\x09Name'), isNull); // TAB
        expect(sanitiseDeviceName('Device\x1BName'), isNull); // ESC
        expect(sanitiseDeviceName('Device\x1FName'), isNull);
      });

      test('rejects DEL (0x7F) and C1 control characters (0x80 - 0x9F)', () {
        expect(sanitiseDeviceName('\x7F'), isNull);
        expect(sanitiseDeviceName('Device\x7FName'), isNull);
        expect(sanitiseDeviceName('Device\u0080Name'), isNull);
        expect(sanitiseDeviceName('Device\u009FName'), isNull);
        expect(sanitiseDeviceName('Device\u009BName'), isNull); // C1 CSI
      });

      test('rejects ANSI escape sequences', () {
        expect(sanitiseDeviceName('\x1B[31mRed Alert\x1B[0m'), isNull);
        expect(sanitiseDeviceName('\x1B[2J'), isNull);
        expect(sanitiseDeviceName('\x1B]0;Evil Title\x07'), isNull);
        expect(sanitiseDeviceName('\u009B1mBold Text'), isNull);
        expect(sanitiseDeviceName('\x1B[?25h'), isNull);
      });
    });

    group('rejections: line breaks', () {
      test('rejects line feed and carriage return', () {
        expect(sanitiseDeviceName('Device\nName'), isNull);
        expect(sanitiseDeviceName('Device\r\nName'), isNull);
        expect(sanitiseDeviceName('Device\rName'), isNull);
        expect(sanitiseDeviceName('\nDevice'), isNull);
        expect(sanitiseDeviceName('Device\n'), isNull);
      });

      test('rejects Unicode line breaks (NEL, LS, PS)', () {
        expect(sanitiseDeviceName('Device\u0085Name'), isNull); // Next Line
        expect(
            sanitiseDeviceName('Device\u2028Name'), isNull); // Line Separator
        expect(sanitiseDeviceName('Device\u2029Name'),
            isNull); // Paragraph Separator
      });
    });

    group('rejections: length cap (> 64 characters)', () {
      test('rejects strings with 65 ASCII characters', () {
        final name65 = 'A' * 65;
        expect(sanitiseDeviceName(name65), isNull);
      });

      test('rejects strings with 65 emoji characters', () {
        final name65 = '🎮' * 65;
        expect(sanitiseDeviceName(name65), isNull);
      });

      test('rejects strings with 65 multi-codepoint grapheme clusters', () {
        final flags65 = '🇺🇸' * 65;
        expect(sanitiseDeviceName(flags65), isNull);

        final thumbs65 = '👍🏽' * 65;
        expect(sanitiseDeviceName(thumbs65), isNull);
      });
    });
  });
}
