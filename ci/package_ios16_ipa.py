import json, pathlib, plistlib, re, subprocess

def version(text):
    return tuple(map(int, (text + '.0.0').split('.')[:3]))

app = pathlib.Path('DerivedData/Build/Products/Release-iphoneos/Trace.app')
app_info = plistlib.loads((app / 'Info.plist').read_bytes())
app_group = app_info.get('AppGroupIdentifier') or 'group.' + app_info['CFBundleIdentifier']
sources = {'Trace.app': 'Trace/Trace.entitlements', 'TraceVPN.appex': 'TraceVPN/TraceVPN.entitlements', 'TraceWidgetExtension.appex': 'TraceWidget/TraceWidget.entitlements'}
bundles = sorted(list(app.rglob('*.framework')) + list(app.rglob('*.appex')), key=lambda p: len(p.parts), reverse=True) + [app]
assert set(sources) <= {p.name for p in bundles}, 'Missing the app, packet tunnel, or widget'
records = []
keychain_groups = {}
for bundle in bundles:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    minimum = info.get('MinimumOSVersion')
    if bundle.name in sources:
        assert minimum, f'{bundle.name}: missing MinimumOSVersion'
    if minimum:
        assert version(minimum) <= (16, 0, 0), (str(bundle), minimum)
    executable = bundle / info['CFBundleExecutable']
    result = subprocess.run(['xcrun', 'vtool', '-show-build', str(executable)], capture_output=True, text=True, check=True)
    min_versions = re.findall(r'^\s*minos\s+(\d+(?:\.\d+){0,2})\s*$', result.stdout, re.MULTILINE)
    assert min_versions and all(version(v) <= (16, 0, 0) for v in min_versions), (str(bundle), result.stdout)
    records.append({'bundle': bundle.name, 'id': info.get('CFBundleIdentifier'), 'minimumOS': minimum, 'macho': result.stdout})
    command = ['codesign', '--force', '--sign', '-']
    source = sources.get(bundle.name)
    if source:
        assert info.get('AppGroupIdentifier', app_group) == app_group, f'{bundle.name}: different application group'
        assert '$(' not in app_group and app_group.startswith('group.'), app_group
        text = pathlib.Path(source).read_text().replace('$(APP_GROUP_IDENTIFIER)', app_group).replace('$(AppIdentifierPrefix)', '')
        groups = plistlib.loads(text.encode()).get('keychain-access-groups', [])
        if bundle.name in ('Trace.app', 'TraceVPN.appex'):
            assert len(groups) == 1 and groups[0] == 'com.justin.trace', (bundle.name, groups)
            # Ad-hoc/TrollStore builds have no Apple Team ID prefix.
            # Use the exact entitlement instead of inferring "com." as a Team ID.
            info['TraceKeychainAccessGroup'] = groups[0]
            (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
            keychain_groups[bundle.name] = groups[0]
            records[-1]['keychainAccessGroup'] = groups[0]
        assert info['CFBundleVersion'] == '17', (bundle.name, info['CFBundleVersion'])
        entitlements = pathlib.Path('ci-logs') / (bundle.name + '.entitlements.plist')
        entitlements.write_text(text)
        command += ['--entitlements', str(entitlements)]
    subprocess.run(command + [str(bundle)], check=True)
assert keychain_groups == {'Trace.app': 'com.justin.trace', 'TraceVPN.appex': 'com.justin.trace'}
pathlib.Path('ci-logs/bundles.json').write_text(json.dumps(records, indent=2))
print(json.dumps(records, indent=2))
