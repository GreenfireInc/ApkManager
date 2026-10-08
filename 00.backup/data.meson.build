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
  gtk_update_icon_cache: true,
  update_desktop_database: true
)

install_data('../public/icons/androidRobot.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
  rename: 'com.github.ApkManager.svg'
)
