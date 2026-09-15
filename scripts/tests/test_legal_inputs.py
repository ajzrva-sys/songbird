import hashlib
import json
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegalInputTests(unittest.TestCase):
    def test_controlled_flac_ogg_source_notices_are_verbatim(self):
        text = (ROOT / 'THIRD_PARTY_NOTICES.txt').read_text(encoding='utf-8')
        for name in ('Vendor/FLAC/source/flac/COPYING.Xiph', 'Vendor/FLAC/source/ogg/COPYING'):
            self.assertIn((ROOT / name).read_text(encoding='utf-8'), text)
        self.assertIn('THE OggVorbis SOURCE CODE IS (C) COPYRIGHT 1994-2018', text)
        self.assertIn('Ross Williams (ross@guest.adelaide.edu.au)', text)

    def test_discogs_usage_notice_is_delivered(self):
        notice = "This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC."
        for name in ('README.md', 'THIRD_PARTY_NOTICES.txt'):
            self.assertIn(notice, (ROOT / name).read_text(encoding='utf-8'))

    def test_nested_notices_are_delivered_without_relicensing(self):
        text = (ROOT / 'THIRD_PARTY_NOTICES.txt').read_text(encoding='utf-8')
        self.assertIn('Copyright Takuya OOURA, 1996-2001', text)
        self.assertIn('You may use, copy, modify and distribute this code for any purpose', text)
        self.assertIn('https://www.kurims.kyoto-u.ac.jp/~ooura/fft.tgz', text)
        for name in ('pitchfcomb.c', 'pitchschmitt.c'):
            source = (ROOT / 'Vendor/aubio/src/src/pitch' / name).read_text(encoding='utf-8')
            self.assertIn(source.split('*/', 1)[0] + '*/', text)
        grdb = Path(os.environ.get('GRDB_SOURCE', str(ROOT / 'Vendor/GRDB.swift'))).resolve()
        inflections = (grdb / 'GRDB/Utils/Inflections+English.swift').read_text(encoding='utf-8')
        self.assertIn(''.join(inflections.splitlines(keepends=True)[:43]), text)
        self.assertIn('Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors', text)
        self.assertIn('Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors', text)
        begin = 'BEGIN VERBATIM SWIFT LICENSE\n'
        end = 'END VERBATIM SWIFT LICENSE'
        self.assertIn(begin, text)
        self.assertIn(end, text)
        license_text = text.split(begin, 1)[1].split(end, 1)[0]
        self.assertEqual(hashlib.sha256(license_text.encode('utf-8')).hexdigest(),
                         '167beb36f181bd163c93c6feb45c68e5f9462fe1af55b278f7bfd1df20e673a3')

    def test_full_license_and_actual_component_notices(self):
        grdb = Path(os.environ.get('GRDB_SOURCE', str(ROOT / 'Vendor/GRDB.swift'))).resolve()
        self.assertTrue((grdb / 'LICENSE').is_file(), 'Supply the verified GRDB source snapshot')
        pins = json.loads((ROOT / 'Package.resolved').read_text())['pins']
        pin = next(p for p in pins if p['identity'] == 'grdb.swift')
        self.assertEqual(pin['state']['revision'], '2cf6c756e1e5ef6901ebae16576a7e4e4b834622')
        license_path = ROOT / 'LICENSE'
        self.assertTrue(license_path.is_file(), 'Full project GPL text is missing')
        self.assertEqual(license_path.read_bytes(), (ROOT / 'Vendor/aubio/src/COPYING').read_bytes())
        notice = (ROOT / 'NOTICE.txt').read_text(encoding='utf-8')
        self.assertIn('Copyright (C) 2026 Andrew Zimmerman', notice)
        self.assertIn('GPL-3.0-or-later', notice)
        self.assertIn('WITHOUT ANY WARRANTY', notice)
        self.assertIn('redistribute', notice)
        third_party = (ROOT / 'THIRD_PARTY_NOTICES.txt').read_text(encoding='utf-8')
        self.assertIn((ROOT / 'Vendor/FLAC/NOTICE.txt').read_text(encoding='utf-8'), third_party)
        self.assertIn((ROOT / 'Vendor/aubio/NOTICE.txt').read_text(encoding='utf-8'), third_party)
        self.assertIn((grdb / 'LICENSE').read_text(encoding='utf-8'), third_party)


if __name__ == '__main__':
    unittest.main()
