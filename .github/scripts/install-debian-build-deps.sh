#!/usr/bin/env bash
# Install build dependencies for ApkManager on Debian/Ubuntu (CI and local).
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
  devscripts \
  debhelper \
  meson \
  ninja-build \
  valac \
  pkg-config \
  libgtk-4-dev \
  libadwaita-1-dev \
  libgtksourceview-5-dev \
  libglib2.0-dev \
  libjson-glib-dev \
  libgee-0.8-dev \
  libarchive-dev \
  libcairo2-dev \
  curl \
  desktop-file-utils \
  libglib2.0-bin
