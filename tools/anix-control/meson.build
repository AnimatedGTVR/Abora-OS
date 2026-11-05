project('anix-control', ['c', 'vala'], version: '0.1.0', license: 'GPL-3.0-or-later', meson_version: '>= 1.0')
add_project_arguments('-w', language: 'c')
executable('anix-control', 'src/main.vala',
  dependencies: [dependency('gtk4', version: '>= 4.14'), dependency('libadwaita-1', version: '>= 1.6'),
                 dependency('json-glib-1.0'), dependency('gio-2.0')],
  install: true)
install_data('data/org.abora.AnixControl.desktop', install_dir: get_option('datadir') / 'applications')
