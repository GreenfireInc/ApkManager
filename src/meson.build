app_sources = files(
  'main.vala',
  'application.vala',
  'windows/main_window.vala',
  'windows/open_window.vala',
  'windows/manifest_popup.vala'
)

executable('apk-manager',
  core_sources + app_sources,
  dependencies: [
    adw_dep,
    gtk_dep,
    gio_dep,
    glib_dep,
    json_glib_dep,
    gee_dep,
    archive_dep,
    gtksourceview_dep
  ],
  install: true
)
