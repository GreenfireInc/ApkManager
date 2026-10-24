using ApkManager.Core;
using ApkManager.Utils;

namespace ApkManager.Windows {
    private struct DonationWallet {
        string name;
        string ticker;
        string icon_basename;
        string address;
    }

    private class WalletDisplayState : Object {
        public DonationWallet wallet;
        public bool show_ticker_prefix { get; set; default = false; }

        public WalletDisplayState(DonationWallet wallet) {
            this.wallet = wallet;
        }

        public string display_address {
            owned get {
                return show_ticker_prefix ? prefixed_address(wallet) : wallet.address;
            }
        }

        public static string prefixed_address(DonationWallet wallet) {
            return "%s://%s".printf(wallet.ticker, wallet.address);
        }

        public void toggle() {
            show_ticker_prefix = !show_ticker_prefix;
        }
    }

    public class DonationsDialog : Adw.Dialog {
        private static DonationWallet[] wallets = {
            { "Bitcoin Cash", "BCH", "bch.svg", "1PHveXq678AcmhmoGupo36hpovU3mSK3tz" },
            { "Bitcoin", "BTC", "btc.svg", "1PHveXq678AcmhmoGupo36hpovU3mSK3tz" },
            { "Litecoin", "LTC", "ltc.svg", "LdmVDneQWKJf2T98KNV6BtRetpDtrHTZQK" },
            { "Ethereum", "ETH", "eth.svg", "0xD0607e1C8d2e6db204Db80A891a3014201017423" },
            { "Dogecoin", "DOGE", "doge.svg", "DHS4dKs4sTNEP6JKittxcYJSKr3V1W5ify" },
            { "Tezos", "XTZ", "xtz.svg", "tz1Yypqjtxwp8p7Hg6roJm4GArcAfFhLg9Pr" },
            { "Terra Classic", "LUNC", "lunc.svg", "terra1aacapxkck24yrf7mj06za3wz0fy3dxrll7gcrm" },
            { "Solana", "SOL", "sol.svg", "3BdhtQJPZ6vhWzfj6qQTUqSPdVyVNQ1BnBjTSjdaQyLu" },
            { "Binance Coin", "BNB", "bnb.svg", "0xD0607e1C8d2e6db204Db80A891a3014201017423" }
        };

        public static void open_for(Gtk.Window parent) {
            var dialog = new DonationsDialog();
            dialog.present(parent);
        }

        private const int WALLET_ICON_PX = 32;
        private const string KOFI_WORDMARK = "kofi.wordmark.svg";
        private const int KOFI_WORDMARK_WIDTH_PX = 117;
        private const int QR_VIEW_PX = 264;
        private const int QR_QUIET_ZONE_MODULES = 4;
        private const int QR_LOGO_PX = 40;
        private const int MIN_CONTENT_WIDTH_PX = 560;
        private const int CONTENT_MARGIN_PX = 12;
        // Row padding, prefix icon, QR and copy buttons, and spacing around the subtitle.
        private const int WALLET_ROW_CHROME_PX = 220;

        private Adw.ToastOverlay toast_overlay;
        private Adw.Clamp content_clamp;

        construct {
            title = "Support ApkManager";
            content_height = 640;
            ensure_css();
            build_ui();

            int width = int.max(
                MIN_CONTENT_WIDTH_PX,
                widest_prefixed_address_px() + WALLET_ROW_CHROME_PX + CONTENT_MARGIN_PX * 2
            );
            content_width = width;
            content_clamp.maximum_size = width;
            content_clamp.tightening_threshold = width;
        }

        private void build_ui() {
            var toolbar = new Adw.ToolbarView();
            toolbar.add_top_bar(new Adw.HeaderBar());

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
            content.margin_top = 24;
            content.margin_bottom = 24;
            content.margin_start = CONTENT_MARGIN_PX;
            content.margin_end = CONTENT_MARGIN_PX;

            var crypto_group = new Adw.PreferencesGroup();
            crypto_group.title = "Cryptocurrency";
            crypto_group.description =
                "If ApkManager is useful to you, consider supporting its development. " +
                "Send any of the currencies below to the matching address.";
            foreach (var wallet in wallets) {
                crypto_group.add(build_wallet_row(wallet));
            }
            content.append(crypto_group);

            var platforms_group = new Adw.PreferencesGroup();
            platforms_group.title = "Other platforms";

            var kofi_row = new Adw.ActionRow();
            kofi_row.title = "Ko-fi";
            kofi_row.subtitle = "ko-fi.com/greenfireinc";
            var kofi_paintable = load_asset_paintable(
                AppPaths.fiat_platform_icon_resource(KOFI_WORDMARK),
                AppPaths.fiat_platform_icon(KOFI_WORDMARK)
            );
            if (kofi_paintable != null) {
                var kofi_logo = new Gtk.Picture.for_paintable(kofi_paintable);
                kofi_logo.content_fit = Gtk.ContentFit.CONTAIN;
                kofi_logo.can_shrink = true;
                kofi_logo.set_size_request(KOFI_WORDMARK_WIDTH_PX, WALLET_ICON_PX);
                kofi_logo.valign = Gtk.Align.CENTER;
                kofi_row.add_prefix(kofi_logo);
            } else {
                var kofi_icon = new Gtk.Image.from_icon_name("web-browser-symbolic");
                kofi_icon.pixel_size = WALLET_ICON_PX;
                kofi_row.add_prefix(kofi_icon);
            }
            var kofi_link = new Gtk.LinkButton.with_label("https://ko-fi.com/greenfireinc", "Open");
            kofi_link.valign = Gtk.Align.CENTER;
            kofi_row.add_suffix(kofi_link);
            platforms_group.add(kofi_row);
            content.append(platforms_group);

            content_clamp = new Adw.Clamp();
            content_clamp.child = content;

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled.vexpand = true;
            scrolled.child = content_clamp;

            toast_overlay = new Adw.ToastOverlay();
            toast_overlay.child = scrolled;
            toolbar.content = toast_overlay;

            child = toolbar;
        }

        private int widest_prefixed_address_px() {
            int widest = 0;
            foreach (var wallet in wallets) {
                var layout = content_clamp.create_pango_layout(
                    WalletDisplayState.prefixed_address(wallet)
                );
                int width, height;
                layout.get_pixel_size(out width, out height);
                widest = int.max(widest, width);
            }
            return widest;
        }

        private Adw.ActionRow build_wallet_row(DonationWallet wallet) {
            var row = new Adw.ActionRow();
            row.title = "%s (%s)".printf(wallet.name, wallet.ticker);
            var state = new WalletDisplayState(wallet);
            row.subtitle = state.display_address;
            row.subtitle_lines = 1;
            row.add_css_class("property");
            row.activatable = true;
            row.tooltip_text = "Click to show as %s://…".printf(wallet.ticker);
            row.activated.connect(() => {
                state.toggle();
            });
            state.notify["show-ticker-prefix"].connect(() => {
                row.subtitle = state.display_address;
            });

            var icon = new Gtk.Image();
            icon.pixel_size = WALLET_ICON_PX;
            icon.set_size_request(WALLET_ICON_PX, WALLET_ICON_PX);
            icon.valign = Gtk.Align.CENTER;
            if (!apply_crypto_icon(icon, wallet.icon_basename)) {
                icon.icon_name = "wallet-symbolic";
            }
            row.add_prefix(icon);

            var qr_button = new Gtk.MenuButton();
            qr_button.icon_name = "qr-code-symbolic";
            qr_button.tooltip_text = "Show QR code";
            qr_button.add_css_class("flat");
            qr_button.valign = Gtk.Align.CENTER;
            qr_button.set_create_popup_func((button) => {
                button.popover = build_qr_popover(state);
            });
            row.add_suffix(qr_button);

            var copy_button = new Gtk.Button.from_icon_name("edit-copy-symbolic");
            copy_button.tooltip_text = "Copy address";
            copy_button.add_css_class("flat");
            copy_button.valign = Gtk.Align.CENTER;
            copy_button.clicked.connect(() => {
                copy_wallet_address(wallet);
            });
            row.add_suffix(copy_button);

            return row;
        }

        private static Gtk.Popover build_qr_popover(WalletDisplayState state) {
            var wallet = state.wallet;
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 12;
            box.margin_end = 12;

            var title = new Gtk.Label("%s (%s)".printf(wallet.name, wallet.ticker));
            title.add_css_class("heading");
            box.append(title);

            QrCode? qr = QrCode.encode_text(state.display_address);

            var area = new Gtk.DrawingArea();
            area.content_width = QR_VIEW_PX;
            area.content_height = QR_VIEW_PX;
            area.set_draw_func((drawing_area, cr, width, height) => {
                if (qr != null) {
                    draw_qr_code(cr, qr, width, height);
                }
            });

            var logo = new Gtk.Image();
            logo.pixel_size = QR_LOGO_PX;
            if (!apply_crypto_icon(logo, wallet.icon_basename)) {
                logo.icon_name = "wallet-symbolic";
            }
            var logo_frame = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            logo_frame.add_css_class("donation-qr-logo");
            logo_frame.halign = Gtk.Align.CENTER;
            logo_frame.valign = Gtk.Align.CENTER;
            logo_frame.append(logo);

            var overlay = new Gtk.Overlay();
            overlay.child = area;
            overlay.add_overlay(logo_frame);
            overlay.visible = qr != null;
            box.append(overlay);

            var unavailable = new Gtk.Label("This address is too long to show as a QR code.");
            unavailable.add_css_class("dim-label");
            unavailable.visible = qr == null;
            box.append(unavailable);

            var address = new Gtk.Label(state.display_address);
            address.wrap = true;
            address.wrap_mode = Pango.WrapMode.CHAR;
            address.max_width_chars = 30;
            address.justify = Gtk.Justification.CENTER;
            address.add_css_class("monospace");
            address.add_css_class("caption");
            address.tooltip_text = "Click to toggle the %s:// prefix".printf(wallet.ticker);
            address.set_cursor_from_name("pointer");
            var address_click = new Gtk.GestureClick();
            address_click.released.connect(() => {
                state.toggle();
            });
            address.add_controller(address_click);
            box.append(address);

            state.notify["show-ticker-prefix"].connect(() => {
                qr = QrCode.encode_text(state.display_address);
                overlay.visible = qr != null;
                unavailable.visible = qr == null;
                address.label = state.display_address;
                area.queue_draw();
            });

            var popover = new Gtk.Popover();
            popover.child = box;
            return popover;
        }

        private static void draw_qr_code(Cairo.Context cr, QrCode qr, int width, int height) {
            int modules = qr.size + QR_QUIET_ZONE_MODULES * 2;
            int cell = int.max(1, int.min(width, height) / modules);
            int drawn = cell * modules;
            int origin_x = (width - drawn) / 2;
            int origin_y = (height - drawn) / 2;

            cr.set_antialias(Cairo.Antialias.NONE);
            cr.set_source_rgb(1, 1, 1);
            cr.rectangle(origin_x, origin_y, drawn, drawn);
            cr.fill();

            cr.set_source_rgb(0, 0, 0);
            for (int y = 0; y < qr.size; y++) {
                for (int x = 0; x < qr.size; x++) {
                    if (qr.get_module(x, y)) {
                        cr.rectangle(
                            origin_x + (x + QR_QUIET_ZONE_MODULES) * cell,
                            origin_y + (y + QR_QUIET_ZONE_MODULES) * cell,
                            cell,
                            cell
                        );
                    }
                }
            }
            cr.fill();
        }

        private static bool css_installed = false;

        private static void ensure_css() {
            if (css_installed) {
                return;
            }
            css_installed = true;

            var css = new Gtk.CssProvider();
            css.load_from_string("""
                .donation-qr-logo {
                    background-color: #ffffff;
                    border-radius: 10px;
                    padding: 4px;
                }
            """);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private static bool apply_crypto_icon(Gtk.Image image, string icon_basename) {
            var paintable = load_asset_paintable(
                AppPaths.crypto_icon_resource(icon_basename),
                AppPaths.crypto_icon(icon_basename)
            );
            if (paintable == null) {
                return false;
            }
            image.set_from_paintable(paintable);
            return true;
        }

        private static Gdk.Paintable? load_asset_paintable(string? resource, string? icon_path) {
            if (resource != null) {
                try {
                    var bytes = GLib.resources_lookup_data(resource, ResourceLookupFlags.NONE);
                    return Gdk.Texture.from_bytes(bytes);
                } catch (Error e) {
                    warning("Could not load icon %s: %s", resource, e.message);
                }
            }

            if (icon_path != null && FileUtils.test(icon_path, FileTest.EXISTS)) {
                try {
                    return Gdk.Texture.from_filename(icon_path);
                } catch (Error e) {
                    warning("Could not load icon file %s: %s", icon_path, e.message);
                }
            }
            return null;
        }

        private void copy_wallet_address(DonationWallet wallet) {
            var clipboard = Gdk.Display.get_default().get_clipboard();
            clipboard.set_text(wallet.address);
            toast_overlay.add_toast(new Adw.Toast("%s address copied".printf(wallet.ticker)));
        }
    }
}
