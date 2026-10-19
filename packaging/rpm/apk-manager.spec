Name:           apk-manager
Version:        0.1.0
Release:        1%{?dist}
Summary:        Inspect Android APK package contents on Linux

License:        GPL-3.0-or-later
URL:            https://github.com/
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  vala
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1) >= 1.4
BuildRequires:  pkgconfig(gtksourceview-5)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(json-glib-1.0)
BuildRequires:  pkgconfig(gee-0.8)
BuildRequires:  pkgconfig(libarchive)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  curl
BuildRequires:  desktop-file-utils
BuildRequires:  glib2-devel

Requires:       java-17-openjdk-headless
Requires:       hicolor-icon-theme

%description
ApkManager is a native GTK 4 / Libadwaita desktop application for reading
Android APK files. It lists raw archive contents instantly and uses Apktool
to decode manifests, resources, and smali for deeper inspection.

%prep
%autosetup -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install

%files
%license COPYING
%doc README.md
%{_bindir}/apk-manager
%{_libdir}/apk-manager/apktool.jar
%{_datadir}/applications/com.github.ApkManager.desktop
%{_datadir}/metainfo/com.github.ApkManager.metainfo.xml
%{_datadir}/glib-2.0/schemas/com.github.ApkManager.gschema.xml
%{_datadir}/icons/hicolor/scalable/apps/com.github.ApkManager.svg
%{_datadir}/icons/hicolor/scalable/mimetypes/application-vnd.android.package-archive.svg
%{_datadir}/mime/packages/application-vnd.android.package-archive.xml
%{_datadir}/thumbnailers/com.github.ApkManager.thumbnailer
%{_datadir}/apk-manager/

%post
/usr/bin/glib-compile-schemas %{_datadir}/glib-2.0/schemas &>/dev/null || :
/usr/bin/update-desktop-database -q %{_datadir}/applications &>/dev/null || :
/usr/bin/update-mime-database %{_datadir}/mime &>/dev/null || :

%postun
/usr/bin/glib-compile-schemas %{_datadir}/glib-2.0/schemas &>/dev/null || :
/usr/bin/update-desktop-database -q %{_datadir}/applications &>/dev/null || :
/usr/bin/update-mime-database %{_datadir}/mime &>/dev/null || :

%changelog
* Sat Oct 18 2026 Corey Stedman <cordesir@gmail.com> - 0.1.0-1
- Initial RPM package for ApkManager 0.1.0
