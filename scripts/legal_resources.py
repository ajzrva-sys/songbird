from pathlib import Path
import argparse
import shutil

LEGAL = {
    'GPL-3.0.txt': 'LICENSE',
    'Songbird-NOTICE.txt': 'NOTICE.txt',
    'THIRD-PARTY-NOTICES.txt': 'THIRD_PARTY_NOTICES.txt',
    'CORRESPONDING-SOURCE.txt': 'SOURCE_CODE.md',
}


def regular_bytes(path):
    path = Path(path)
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Symlink rejected: ' + str(path))
    if not path.is_file():
        raise ValueError('Missing regular file: ' + str(path))
    data = path.read_bytes()
    if not data.decode('utf-8').strip():
        raise ValueError('Empty legal text: ' + str(path))
    return data


def check(root, destination):
    destination = Path(destination)
    if not destination.is_dir():
        raise ValueError('Missing legal directory')
    if {p.name for p in destination.iterdir()} != set(LEGAL):
        raise ValueError('Legal file set mismatch')
    for name, original in LEGAL.items():
        if regular_bytes(Path(root) / original) != regular_bytes(destination / name):
            raise ValueError('Legal text mismatch: ' + name)


def stage(root, destination):
    destination = Path(destination)
    check(root, Path(root) / 'Sources/Resources/Legal')
    if destination.exists() or destination.is_symlink():
        raise ValueError('Legal destination must be new')
    if any(p.is_symlink() for p in destination.parents):
        raise ValueError('Symlink destination parent')
    shutil.copytree(Path(root) / 'Sources/Resources/Legal', destination)
    check(root, destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('check', 'stage'))
    parser.add_argument('root', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        {'check': check, 'stage': stage}[args.action](args.root, args.destination)
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
