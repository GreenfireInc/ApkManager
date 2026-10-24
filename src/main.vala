using ApkManager.Core;

int main(string[] args) {
    var dbus_addr = GLib.Environment.get_variable("DBUS_SESSION_BUS_ADDRESS");
    if (dbus_addr != null && dbus_addr.has_prefix("unix:path=")) {
        var socket_path = dbus_addr.substring("unix:path=".length);
        if (!GLib.FileUtils.test(socket_path, GLib.FileTest.EXISTS)) {
            GLib.Environment.unset_variable("DBUS_SESSION_BUS_ADDRESS");
        }
    }

    // Answered before GApplication startup, which initializes GTK and needs a display.
    if (wants_version(args)) {
        stdout.printf("ApkManager %s\n", APPLICATION_VERSION);
        return 0;
    }

    var thumbnail_status = FileManagerIcons.handle_thumbnail_cli(args);
    if (thumbnail_status != null) {
        return thumbnail_status;
    }

    ApkManager.Application.retire_stale_instance();
    var app = new ApkManager.Application();
    return app.run(args);
}

bool wants_version(string[] args) {
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--") {
            return false;
        }
        if (args[i] == "--version") {
            return true;
        }
    }
    return false;
}
