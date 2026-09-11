"""Finder layout for the manual installer; no changes to the bundled app."""
from pathlib import Path

app = Path(defines['app'])
format = 'UDZO'
filesystem = 'HFS+'
files = [str(app)]
symlinks = {'Applications': '/Applications'}
icon = str(app / 'Contents/Resources/AppIcon.icns')
background = defines['background']
window_rect = ((200, 160), (640, 400))
icon_locations = {'Codex Accounts.app': (160, 205), 'Applications': (480, 205)}
icon_size = 112
text_size = 13
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
