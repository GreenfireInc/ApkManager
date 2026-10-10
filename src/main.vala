using ApkManager.Core;

int main(string[] args) {
    var dbus_addr = GLib.Environment.get_variable("DBUS_SESSION_BUS_ADDRESS");
    if (dbus_addr != null && dbus_addr.has_prefix("unix:path=")) {
        var socket_path = dbus_addr.substring("unix:path=".length);
        if (!GLib.FileUtils.test(socket_path, GLib.FileTest.EXISTS)) {
            GLib.Environment.unset_variable("DBUS_SESSION_BUS_ADDRESS");
        }
    }

    ApkManager.Application.retire_stale_instance();
    var app = new ApkManager.Application();
    return app.run(args);
}
