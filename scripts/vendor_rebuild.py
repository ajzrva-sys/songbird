#!/usr/bin/env python3
"""Shared path/evidence boundary for the two controlled vendor recipes."""
import argparse
from pathlib import Path
import sys
import stat
import hashlib
import json
import os
import re
import tempfile
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def checked_path(value, kind):
    """Reject aliases before resolution; never follow input/destination links."""
    p = Path(value)
    if not p.is_absolute() or str(p) != value or '..' in p.parts or p == Path('/'):
        raise ValueError('path must be canonical and absolute: ' + value)
    for ancestor in [p, *p.parents]:
        if ancestor.is_symlink():
            raise ValueError('symlink path: ' + str(ancestor))
    if kind == 'new':
        if p.exists() or not p.parent.is_dir():
            raise ValueError('destination must be new with an existing parent: ' + value)
    elif kind == 'directory':
        if not p.is_dir():
            raise ValueError('source directory missing: ' + value)
        for child in p.rglob('*'):
            mode = child.lstat().st_mode
            if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)) or (child.is_file() and child.stat().st_nlink != 1):
                raise ValueError('unsafe source entry: ' + str(child))
    elif not p.is_file() or p.stat().st_nlink != 1:
        raise ValueError('expected unlinked regular file: ' + value)
    return p


def overlap(a, b):
    return a == b or a in b.parents or b in a.parents


def validate_build(args):
    args.output = checked_path(args.output_dir, 'new')
    args.evidence = checked_path(args.evidence_dir, 'new')
    if args.component == 'flac-ogg' and not args.source_dir:
        raise ValueError('FLAC/ogg requires explicit --source-dir containing flac/ and ogg/')
    args.source = checked_path(args.source_dir or str(ROOT/'Vendor/aubio/src'), 'directory')
    if args.component == 'aubio':
        for relative in ['VERSION', 'src/aubio.h']:
            checked_path(str(args.source/relative), 'file')
        for relative in ['scripts/aubio-cmake/CMakeLists.txt', 'scripts/aubio-cmake/config.h.in']:
            checked_path(str(ROOT/relative), 'file')
    else:
        ledger = checked_path(str(ROOT/'publication/vendor-source-imports.json'), 'file')
        entries = json.loads(ledger.read_text())['imports']
        if len(entries) != 2 or {x['component'] for x in entries} != {'flac', 'ogg'}:
            raise ValueError('source inventory must identify exactly flac and ogg')
        for item in entries:
            source = checked_path(str(args.source/item['component']), 'directory')
            if inventory(source) != item['files']:
                raise ValueError('source inventory mismatch: '+item['component'])
    if overlap(args.output, args.evidence) or any(overlap(dst, src) for dst in [args.output,args.evidence] for src in [ROOT,args.source]):
        raise ValueError('source, project, output and evidence destinations must not collide')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def adopt(args):
    if args.output_dir or args.evidence_dir or args.source_dir:
        raise ValueError('adoption and build options are mutually exclusive')
    if not args.expected_sha256 or not re.fullmatch('[0-9a-f]{64}', args.expected_sha256) or not args.backup_dir:
        raise ValueError('adoption requires an exact lowercase SHA-256 and a new external --backup-dir')
    source = checked_path(args.install_reviewed_output, 'file')
    backup = checked_path(args.backup_dir, 'new')
    if args.component == 'aubio':
        vendor_relative = 'Vendor/aubio/libaubio.5.dylib'
    else:
        if source.name not in {'libFLAC.14.dylib', 'libogg.0.dylib'}:
            raise ValueError('reviewed FLAC/ogg input must have its ABI basename')
        vendor_relative = 'Vendor/FLAC/'+source.name
    vendor = checked_path(str(ROOT/vendor_relative), 'file')
    if overlap(backup, ROOT) or overlap(backup, source) or overlap(source, ROOT):
        raise ValueError('reviewed input and backup must be external and noncolliding')
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != args.expected_sha256:
        raise ValueError('reviewed output SHA-256 mismatch')
    if args.validate_options:
        return
    original = vendor.read_bytes()
    backup.mkdir(mode=0o700)
    saved = backup/vendor.name
    with saved.open('xb') as f:
        f.write(original)
    before = hashlib.sha256(original).hexdigest()
    if sha(saved) != before or sha(vendor) != before:
        raise ValueError('backup or vendor changed; refusing adoption')
    receipt = {'status': 'backup-preserved', 'vendor': str(vendor), 'source': str(source),
               'before_sha256': before, 'expected_sha256': args.expected_sha256}
    write_json(backup/'adoption.json', receipt)
    fd, staged = tempfile.mkstemp(prefix='.reviewed-', dir=vendor.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush(); os.fsync(f.fileno())
        os.chmod(staged, stat.S_IMODE(vendor.stat().st_mode))
        os.replace(staged, vendor)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)
    receipt['after_sha256'] = sha(vendor)
    receipt['status'] = 'installed' if receipt['after_sha256'] == args.expected_sha256 else 'verification-failed'
    write_json(backup/'adoption.json', receipt)
    if receipt['status'] != 'installed':
        raise ValueError('installed output hash mismatch; backup retained')
    print('reviewed bytes installed; backup and receipt: ' + str(backup))


def inventory(root):
    return [{'path': str(p.relative_to(root)), 'sha256': sha(p), 'bytes': p.stat().st_size,
             'mode': stat.S_IMODE(p.stat().st_mode)} for p in sorted(root.rglob('*'), key=lambda p: p.relative_to(root).as_posix()) if p.is_file()]


class Build:
    """Retain every command, generated directory, and output transformation."""
    def __init__(self, args):
        self.args = args
        self.evidence = args.evidence
        self.cmake = shutil.which('cmake')
        if not self.cmake:
            raise ValueError('cmake not found on PATH; install it before rebuilding')
        for p in ['/usr/bin/clang', '/usr/bin/make', '/usr/bin/xcrun', '/usr/bin/otool', '/usr/bin/vtool', '/usr/bin/lipo', '/usr/bin/install_name_tool']:
            if not os.access(p, os.X_OK):
                raise ValueError('required executable missing: ' + p)
        self.evidence.mkdir(mode=0o700)
        args.output.mkdir(mode=0o700)
        for d in ['home', 'tmp', 'empty-pkgconfig']:
            (self.evidence/d).mkdir(mode=0o700)
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.evidence/'home'),
                    'CFFIXED_USER_HOME': str(self.evidence/'home'), 'TMPDIR': str(self.evidence/'tmp'),
                    'LANG': 'C', 'LC_ALL': 'C', 'MACOSX_DEPLOYMENT_TARGET': '14.0',
                    'PKG_CONFIG_PATH': '', 'PKG_CONFIG_LIBDIR': str(self.evidence/'empty-pkgconfig')}
        write_json(self.evidence/'environment.json', self.env)
        self.receipt = {'status': 'in-progress', 'component': args.component,
                        'invocation': sys.argv, 'outputs': [], 'install_stages': []}
        write_json(self.evidence/'receipt.json', self.receipt)
        self.number = 0
        self.inputs = {'source': inventory(args.source),
                       'recipe': inventory(ROOT/'scripts/aubio-cmake') if args.component == 'aubio' else [],
                       'scripts': [{'path': 'scripts/'+name, 'sha256': sha(ROOT/'scripts'/name)}
                                   for name in ['vendor_rebuild.py', 'rebuild-'+args.component+'.sh']]}
        if args.component == 'flac-ogg':
            self.inputs['import_ledger_sha256'] = sha(ROOT/'publication/vendor-source-imports.json')
        write_json(self.evidence/'source-inputs.json', self.inputs)
        tools = {}
        for name, cmd in [('cmake', [self.cmake, '--version']), ('clang', ['/usr/bin/clang', '--version']),
                          ('sdk', ['/usr/bin/xcrun', '--show-sdk-path']), ('sdk_version', ['/usr/bin/xcrun', '--show-sdk-version']),
                          ('os', ['/usr/bin/sw_vers']), ('machine', ['/usr/bin/uname', '-m'])]:
            tools[name] = {'argv': cmd, 'output': self.run(cmd), 'executable_sha256': sha(Path(cmd[0]))}
        write_json(self.evidence/'toolchain.json', tools)
        self.common = ['-G', 'Unix Makefiles', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_OSX_ARCHITECTURES=arm64',
                       '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
                       '-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF', '-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF',
                       '-DCMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH=OFF', '-DCMAKE_PREFIX_PATH=',
                       '-DCMAKE_C_COMPILER=/usr/bin/clang', '-DCMAKE_CXX_COMPILER=/usr/bin/clang++',
                       '-DCMAKE_MAKE_PROGRAM=/usr/bin/make', '-DCMAKE_OSX_SYSROOT='+tools['sdk']['output'].strip(),
                       '-DCMAKE_INSTALL_NAME_DIR=@rpath', '-DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON']

    def run(self, argv):
        argv = [str(x) for x in argv]
        self.number += 1
        log = self.evidence/('%03d.log' % self.number)
        with log.open('x') as f:
            result = subprocess.run(argv, cwd=self.evidence, env=self.env, stdout=f, stderr=subprocess.STDOUT)
        with (self.evidence/'commands.jsonl').open('a') as f:
            f.write(json.dumps({'argv': argv, 'cwd': str(self.evidence), 'environment': 'environment.json',
                                'returncode': result.returncode, 'log': log.name})+'\n')
        output = log.read_text(errors='replace')
        if result.returncode:
            self.receipt['status'] = 'failed'; self.receipt['failed_command'] = argv
            write_json(self.evidence/'receipt.json', self.receipt)
            raise ValueError('command failed; retained log: '+str(log)+'\n'+output[-4000:])
        return output

    def inspect(self, binary):
        return {'path': str(binary), 'sha256': sha(binary),
                'archs': self.run(['/usr/bin/lipo', '-archs', binary]),
                'id': self.run(['/usr/bin/otool', '-D', binary]),
                'dependencies': self.run(['/usr/bin/otool', '-L', binary]),
                'load_commands': self.run(['/usr/bin/otool', '-l', binary]),
                'build_version': self.run(['/usr/bin/vtool', '-show-build', binary])}

    def output(self, built, name):
        out = self.args.output/name
        shutil.copy2(built, out)
        before = self.inspect(out)
        desired = '@rpath/'+name
        changed = before['id'].splitlines()[1].strip() != desired
        if changed:
            self.run(['/usr/bin/install_name_tool', '-id', desired, out])
        after = self.inspect(out)
        record = {'pre': before, 'post': after, 'install_name_edit': changed,
                  'built_path': str(built), 'built_sha256': sha(built)}
        self.receipt['outputs'].append(record)
        write_json(self.evidence/'receipt.json', self.receipt)
        if after['archs'].strip() != 'arm64' or 'minos 14.0' not in after['build_version'] or after['id'].splitlines()[1].strip() != desired:
            raise ValueError('output architecture/deployment target/install ID mismatch')
        allowed = {desired, '/usr/lib/libSystem.B.dylib'}
        if name == 'libFLAC.14.dylib':
            allowed.add('@rpath/libogg.0.dylib')
        deps = {line.strip().split(' (')[0] for line in after['dependencies'].splitlines()[1:]}
        if not deps.issubset(allowed):
            raise ValueError('unexpected library linkage: '+str(deps))

    def aubio(self):
        build = self.evidence/'aubio-build'
        self.run([self.cmake, '-S', ROOT/'scripts/aubio-cmake', '-B', build,
                  '-DAUBIO_SOURCE_ROOT='+str(self.args.source), *self.common])
        self.run([self.cmake, '--build', build, '--config', 'Release', '--parallel'])
        self.output(build/'libaubio.5.4.8.dylib', 'libaubio.5.dylib')
        self.finish([build])

    def install(self, build, built, staged):
        stage = {'pre': self.inspect(built)}
        self.receipt['install_stages'].append(stage)
        write_json(self.evidence/'receipt.json', self.receipt)
        self.run([self.cmake, '--install', build, '--config', 'Release'])
        stage['post'] = self.inspect(staged)
        write_json(self.evidence/'receipt.json', self.receipt)

    def flac_ogg(self):
        ogg_build = self.evidence/'ogg-build'
        ogg_stage = self.evidence/'ogg-stage'
        flac_build = self.evidence/'flac-build'
        flac_stage = self.evidence/'flac-stage'
        self.run([self.cmake, '-S', self.args.source/'ogg', '-B', ogg_build, *self.common,
                  '-DBUILD_SHARED_LIBS=ON', '-DBUILD_FRAMEWORK=OFF', '-DBUILD_TESTING=OFF',
                  '-DINSTALL_DOCS=OFF', '-DINSTALL_PKG_CONFIG_MODULE=OFF', '-DINSTALL_CMAKE_PACKAGE_MODULE=OFF',
                  '-DCMAKE_INSTALL_PREFIX='+str(ogg_stage), '-DCMAKE_INSTALL_LIBDIR=lib'])
        self.run([self.cmake, '--build', ogg_build, '--config', 'Release', '--parallel'])
        self.install(ogg_build, ogg_build/'libogg.0.8.6.dylib', ogg_stage/'lib/libogg.0.8.6.dylib')
        self.output(ogg_stage/'lib/libogg.0.dylib', 'libogg.0.dylib')
        ogg_library = ogg_stage/'lib/libogg.dylib'
        ogg_include = ogg_stage/'include'
        staged_hash = sha(ogg_library)
        if staged_hash != self.receipt['outputs'][0]['post']['sha256']:
            raise ValueError('staged ogg and reviewed output must be byte-identical')
        self.run([self.cmake, '-S', self.args.source/'flac', '-B', flac_build, *self.common,
                  '-DBUILD_SHARED_LIBS=ON', '-DBUILD_CXXLIBS=OFF', '-DBUILD_PROGRAMS=OFF',
                  '-DBUILD_EXAMPLES=OFF', '-DBUILD_TESTING=OFF', '-DBUILD_DOCS=OFF', '-DINSTALL_MANPAGES=OFF',
                  '-DINSTALL_PKGCONFIG_MODULES=OFF', '-DINSTALL_CMAKE_CONFIG_MODULE=OFF',
                  '-DWITH_OGG=ON', '-DENABLE_MULTITHREADING=ON', '-DWITH_FORTIFY_SOURCE=ON', '-DWITH_STACK_PROTECTOR=ON',
                  '-DOGG_INCLUDE_DIR:PATH='+str(ogg_include), '-DOGG_LIBRARY:FILEPATH='+str(ogg_library),
                  '-DPKG_CONFIG_EXECUTABLE=/usr/bin/false', '-DCMAKE_DISABLE_FIND_PACKAGE_Intl=ON',
                  '-DCMAKE_INSTALL_PREFIX='+str(flac_stage), '-DCMAKE_INSTALL_LIBDIR=lib'])
        cache = (flac_build/'CMakeCache.txt').read_text()
        compile_commands = (flac_build/'compile_commands.json').read_text()
        link = (flac_build/'src/libFLAC/CMakeFiles/FLAC.dir/link.txt').read_text()
        if ('OGG_INCLUDE_DIR:PATH='+str(ogg_include) not in cache or
                'OGG_LIBRARY:FILEPATH='+str(ogg_library) not in cache or str(ogg_library) not in link or
                str(ogg_include) not in compile_commands or sha(ogg_library) != staged_hash):
            raise ValueError('FLAC did not select the controlled ogg inputs')
        for text in [compile_commands, link]:
            if '/opt/homebrew' in text or '/usr/local' in text:
                raise ValueError('host package path leaked into FLAC compilation/link')
        self.receipt['ogg_linkage'] = {'include': str(ogg_include), 'library': str(ogg_library),
                                       'staged_sha256': staged_hash, 'link_command': link}
        write_json(self.evidence/'receipt.json', self.receipt)
        self.run([self.cmake, '--build', flac_build, '--config', 'Release', '--parallel'])
        self.install(flac_build, flac_build/'src/libFLAC/libFLAC.14.0.0.dylib', flac_stage/'lib/libFLAC.14.0.0.dylib')
        self.output(flac_stage/'lib/libFLAC.14.dylib', 'libFLAC.14.dylib')
        if sha(ogg_library) != staged_hash:
            raise ValueError('controlled ogg changed while building FLAC')
        if '@rpath/libogg.0.dylib' not in self.receipt['outputs'][1]['post']['dependencies']:
            raise ValueError('FLAC is missing its controlled ogg dependency')
        self.finish([ogg_build, ogg_stage, flac_build, flac_stage])

    def finish(self, generated):
        if inventory(self.args.source) != self.inputs['source']:
            raise ValueError('source changed during compilation')
        self.receipt['generated_files'] = {p.name: inventory(p) for p in generated}
        self.receipt['source_inputs_sha256'] = sha(self.evidence/'source-inputs.json')
        self.receipt['status'] = 'built-not-adopted'
        write_json(self.evidence/'receipt.json', self.receipt)
        print('built, inspected, not adopted; evidence: '+str(self.evidence))


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('component', choices=['aubio', 'flac-ogg'])
    parser.add_argument('--validate-options', action='store_true')
    parser.add_argument('--output-dir')
    parser.add_argument('--evidence-dir')
    parser.add_argument('--source-dir')
    parser.add_argument('--install-reviewed-output')
    parser.add_argument('--expected-sha256')
    parser.add_argument('--backup-dir')
    args = parser.parse_args()
    try:
        if args.install_reviewed_output:
            adopt(args)
            return
        if args.expected_sha256 or args.backup_dir:
            raise ValueError('adoption options require --install-reviewed-output')
        if not args.output_dir or not args.evidence_dir:
            raise ValueError('explicit --output-dir and --evidence-dir are required')
        validate_build(args)
        if args.validate_options:
            print('options valid; no tools invoked and no files changed')
            return
        build = Build(args)
        if args.component == 'flac-ogg':
            build.flac_ogg()
        else:
            build.aubio()
    except (ValueError, OSError) as exc:
        parser.error(str(exc))


if __name__ == '__main__':
    main()
