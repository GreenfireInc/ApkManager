project('apk-manager', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>=0.64.0'
)

gnome = import('gnome')

adw_dep = dependency('libadwaita-1', version: '>=1.4')
gio_dep = dependency('gio-2.0')
glib_dep = dependency('glib-2.0')
gtk_dep = dependency('gtk4')
json_glib_dep = dependency('json-glib-1.0')
gee_dep = dependency('gee-0.8')
archive_dep = dependency('libarchive')
gtksourceview_dep = dependency('gtksourceview-5')

add_project_arguments(['--target-glib=2.74', '--pkg=posix'], language: 'vala')
add_project_arguments(['-w'], language: 'c')

apktool_libdir = get_option('prefix') / get_option('libdir') / 'apk-manager'

core_sources = files(
  'src/core/app_constants.vala',
  'src/core/app_paths.vala',
  'src/core/apk_archive.vala',
  'src/core/apktool_runner.vala',
  'src/core/decode_session.vala',
  'src/core/decode_session_registry.vala',
  'src/utils/file_utils.vala'
)

build_info_conf = configuration_data()
build_info_conf.set('VERSION', meson.project_version())
build_info = configure_file(
  input: 'src/core/build_info.vala.in',
  output: 'build_info.vala',
  configuration: build_info_conf
)
core_sources += build_info

fetch_apktool_script = files('scripts/fetch-apktool.sh')
apktool_jar = custom_target('apktool-jar',
  output: 'apktool.jar',
  build_by_default: true,
  command: ['sh', fetch_apktool_script, meson.current_build_dir()],
  install: true,
  install_dir: apktool_libdir
)

subdir('data')
subdir('src')
