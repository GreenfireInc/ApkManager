desktop_conf = configuration_data()
desktop_conf.set('bindir', join_paths(get_option('prefix'), get_option('bindir')))

desktop_file = configure_file(
  input: 'com.github.ApkManager.desktop.in',
  output: 'com.github.ApkManager.desktop',
  configuration: desktop_conf
)

install_data(desktop_file,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

install_data('com.github.ApkManager.metainfo.xml',
  install_dir: join_paths(get_option('datadir'), 'metainfo')
)

install_data('mime/application-vnd.android.package-archive.xml',
  install_dir: join_paths(get_option('datadir'), 'mime', 'packages')
)

thumbnailer_conf = configuration_data()
thumbnailer_conf.set('bindir', join_paths(get_option('prefix'), get_option('bindir')))
thumbnailer_file = configure_file(
  input: 'com.github.ApkManager.thumbnailer.in',
  output: 'com.github.ApkManager.thumbnailer',
  configuration: thumbnailer_conf
)
install_data(thumbnailer_file,
  install_dir: join_paths(get_option('datadir'), 'thumbnailers')
)

install_data('../public/assets/icons/operatingSystems/android.svg',
  install_dir: join_paths(get_option('datadir'), 'apk-manager', 'icons', 'operatingSystems')
)

install_data('../public/assets/icons/operatingSystems/android.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'mimetypes'),
  rename: 'application-vnd.android.package-archive.svg'
)

gsettings_schemas = files('com.github.ApkManager.gschema.xml')
schema_dir = join_paths(get_option('datadir'), 'glib-2.0', 'schemas')

install_data(gsettings_schemas,
  install_dir: schema_dir
)

compiled_schemas = custom_target('gschemas.compiled',
  input: gsettings_schemas,
  output: 'gschemas.compiled',
  command: [
    find_program('glib-compile-schemas'),
    '--targetdir=@OUTDIR@',
    meson.current_source_dir()
  ],
  install: true,
  install_dir: schema_dir
)

gnome.post_install(
  glib_compile_schemas: true,
  # Do not run gtk-update-icon-cache here. Meson regenerates the entire
  # ~/.local/share/icons/hicolor tree; on user-local prefixes that tree often
  # already holds third-party icons (Wine, manual drops) with names or layouts
  # gtk-update-icon-cache rejects, which aborts meson install even though
  # apk-manager, the desktop file, and apktool.jar are already installed.
  # Our app icon is a single SVG under scalable/apps/ and is picked up without
  # a cache rebuild; run update-desktop-database after install instead.
  gtk_update_icon_cache: false,
  update_desktop_database: true
)

install_data('../public/icons/androidRobot.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
  rename: 'com.github.ApkManager.svg'
)

store_repo_icon_dir = join_paths(get_option('datadir'), 'apk-manager', 'icons', 'storesRepositories')
foreach icon : [
  'appRepo.fdroid.svg',
  'appRepo.aptoide.svg',
  'appRepo.uptodown.svg',
  'appRepo.Izzy.svg',
  'appRepo.openapk.svg'
]
  install_data('../public/assets/icons/storesRepositories/' + icon, install_dir: store_repo_icon_dir)
endforeach
