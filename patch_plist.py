import plistlib
import shutil
import os

app = './xtool/timekeeper.app'

# Patch plist
with open(f'{app}/Info.plist', 'rb') as f:
    plist = plistlib.load(f)

plist['NSLocationWhenInUseUsageDescription'] = 'TimeKeeper uses your location to check which client site you are at when starting a timer.'
plist['NSLocationAlwaysAndWhenInUseUsageDescription'] = 'TimeKeeper uses your location to check which client site you are at when starting a timer.'
plist['NSLocationTemporaryFullAccuracyUsageDescription'] = 'TimeKeeper needs precise location to match you to a client work site.'
plist['CFBundleIconFiles'] = ['AppIcon']
plist['CFBundleIconName'] = 'AppIcon'

with open(f'{app}/Info.plist', 'wb') as f:
    plistlib.dump(plist, f)
print('Plist patched')

# Copy icon into app bundle
icon_src = './Resources/AppIcon.png'
if os.path.exists(icon_src):
    shutil.copy(icon_src, f'{app}/AppIcon.png')
    shutil.copy(icon_src, f'{app}/AppIcon@2x.png')
    shutil.copy(icon_src, f'{app}/AppIcon@3x.png')
    print('Icon copied into bundle')
else:
    print(f'WARNING: Icon not found at {icon_src}')
