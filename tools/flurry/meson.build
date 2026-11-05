project('flurry', ['c', 'vala'],
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 1.0')

app_id = 'io.github.AnimatedGTVR.Flurry'

add_project_arguments('-DGETTEXT_PACKAGE="flurry"', '-w', language: 'c')

conf = configuration_data()
conf.set('VERSION', meson.project_version())
config_vala = configure_file(input: 'src/config.vala.in', output: 'config.vala', configuration: conf)

deps = [
  dependency('gtk4', version: '>= 4.14'),
  dependency('libadwaita-1', version: '>= 1.6'),
  dependency('json-glib-1.0'),
  dependency('gio-2.0'),
  meson.get_compiler('vala').find_library('posix'),
]

executable('flurry',
  config_vala,
  'src/main.vala',
  'src/proc.vala',
  'src/model.vala',
  'src/nix.vala',
  'src/flatpak.vala',
  'src/snap.vala',
  'src/store.vala',
  'src/widgets.vala',
  'src/details.vala',
  'src/prefs.vala',
  'src/window.vala',
  'src/style.vala',
  dependencies: deps,
  vala_args: ['--target-glib=2.80'],
  install: true)

datadir = get_option('datadir')
install_data('data' / app_id + '.desktop', install_dir: datadir / 'applications')
install_data('data' / app_id + '.metainfo.xml', install_dir: datadir / 'metainfo')
install_data('data/icons/app' / app_id + '.svg', install_dir: datadir / 'icons/hicolor/scalable/apps')
install_subdir('data/icons/symbolic', install_dir: datadir / 'icons/hicolor/symbolic/apps', strip_directory: true)
