import pathlib, re, subprocess

xcframework = pathlib.Path('build/quiche/quiche.xcframework')
rust_lib = pathlib.Path(subprocess.check_output(['rustc', '--print', 'target-libdir'], text=True).strip())
nm = rust_lib.parent / 'bin' / 'llvm-nm'
subprocess.run([nm, '--version'], check=True)
verifier = pathlib.Path('Tools/QUIC/verify_quiche_symbols.sh').read_text()
required = set(re.findall(r'^  "(quiche_[a-z0-9_]+)"$', verifier, re.MULTILINE))
if not required:
    raise SystemExit('No required QUIC exports found in the upstream verifier')
slices = [('ios-arm64', 'arm64'), ('ios-arm64_x86_64-simulator', 'arm64'), ('ios-arm64_x86_64-simulator', 'x86_64')]
for directory, arch in slices:
    archive = xcframework / directory / 'libquiche.a'
    print(f'Checking {archive} ({arch})')
    symbols = subprocess.check_output([nm, f'--arch={arch}', '-gUj', archive], text=True)
    exported = {line.removeprefix('_') for line in symbols.splitlines()}
    missing = required - exported
    if missing:
        raise SystemExit(f'{arch}: missing QUIC exports: {", ".join(sorted(missing))}')
    print(f'Verified {len(required)} QUIC exports for {directory}/{arch}')
