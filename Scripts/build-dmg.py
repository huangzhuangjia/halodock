"""Build the styled installer using Finder-compatible metadata (including Tahoe)."""
import sys
from pathlib import Path
import dmgbuild

root = Path(__file__).resolve().parent.parent
dmgbuild.build_dmg(sys.argv[1], 'HaloDockInstaller', settings={
    'files': [str(root / '.build/HaloDock.app')],
    'symlinks': {'Applications': '/Applications'},
    'background': str(root / '.build/installer-background.tiff'),
    'window_rect': ((240, 180), (680, 570)),
    'icon_locations': {'HaloDock.app': (180, 228), 'Applications': (500, 228)},
    'icon_size': 128,
    'text_size': 13,
    'format': 'UDZO',
    'default_view': 'icon-view',
    'filesystem': 'HFS+',
})
