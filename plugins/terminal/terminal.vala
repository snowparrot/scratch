// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE

  Copyright (C) 2011-2013 Mario Guerriero <mario@elementaryos.org>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses/>

  END LICENSE
***/

using Vte;

public const string NAME = _("Terminal");
public const string DESCRIPTION = _("A terminal in your text editor");

public class Scratch.Plugins.Terminal : Peas.ExtensionBase,  Peas.Activatable {

    MainWindow window = null;

    Scratch.Plugins.TerminalViewer.Settings settings;

    Gtk.Notebook? bottombar = null;
    Gtk.Notebook? contextbar = null;
    Scratch.Widgets.Toolbar? toolbar = null;
    Gtk.ToggleToolButton? tool_button = null;

    Gtk.RadioMenuItem location_bottom = null;
    Gtk.RadioMenuItem location_right = null;

    Vte.Terminal terminal;
    Gtk.Grid grid;

    GLib.Pid child_pid;

    private const string SETTINGS_SCHEMA = "io.elementary.terminal.settings";
    private const string LEGACY_SETTINGS_SCHEMA = "org.pantheon.terminal.settings";

    private string font_name = "";

    Scratch.Services.Interface plugins;
    public Object object { owned get; construct; }

    public void update_state () {
    }

    public void activate () {

        plugins = (Scratch.Services.Interface) object;

        plugins.hook_window.connect ((w) => {
            if (window != null)
                return;

            window = w;
            window.key_press_event.connect (switch_focus);
            window.destroy.connect (save_last_working_directory);

        });

        plugins.hook_notebook_bottom.connect ((n) => {
            if (bottombar == null) {
                this.bottombar = n;
                this.bottombar.switch_page.connect ((page, page_num) => {
                    if (tool_button.active != (grid == page) && bottombar.page_num (grid) > -1)
                        tool_button.active = (grid == page);
                });
            }
        });

        plugins.hook_notebook_context.connect ((n) => {
            if (contextbar == null) {
                this.contextbar = n;
                this.contextbar.switch_page.connect ((page, page_num) => {
                    if (tool_button.active != (grid == page) && contextbar.page_num (grid) > -1)
                        tool_button.active = (grid == page);
                });
            }
        });

        plugins.hook_toolbar.connect ((n) => {
            if (toolbar == null) {
                this.toolbar = n;
                on_hook_toolbar (this.toolbar);
            }
        });

        plugins.hook_split_view.connect (on_hook_split_view);

        on_hook_notebook ();
    }

    public void deactivate () {
        if (terminal != null)
            grid.destroy ();

        if (tool_button != null)
            tool_button.destroy ();

        window.key_press_event.disconnect (switch_focus);
        window.destroy.disconnect (save_last_working_directory);
    }

    void save_last_working_directory () {
        settings.last_opened_path = get_shell_location ();
    }

    void move_terminal_bottombar () {
        if (bottombar.page_num (grid) == -1) {
            debug ("Remove Terminal page: %d", contextbar.page_num (grid));
            contextbar.remove_page (contextbar.page_num (grid));
            bottombar.set_current_page (bottombar.append_page (grid, new Gtk.Label (_("Terminal"))));
            debug ("Move Terminal: BOTTOMBAR.");
        }
    }

    void move_terminal_contextbar () {
        if (contextbar.page_num (grid) == -1) {
            debug ("Remove Terminal page: %d", bottombar.page_num (grid));
            bottombar.remove_page (bottombar.page_num (grid));
            contextbar.set_current_page (contextbar.append_page (grid, new Gtk.Label (_("Terminal"))));
            debug ("Move Terminal: CONTEXTBAR.");
        }
    }

    bool switch_focus (Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.t
            && Gdk.ModifierType.MOD1_MASK in event.state
            && Gdk.ModifierType.CONTROL_MASK in event.state) {

            if (terminal.has_focus && window.get_current_document () != null) {

                window.get_current_document ().focus ();
                debug ("Move focus: EDITOR.");
                return true;

            } else if (window.get_current_document () != null && window.get_current_document ().source_view.has_focus) {

                terminal.grab_focus ();
                debug ("Move focus: TERMINAL.");
                return true;

            }
        }
        return false;
    }

    void on_hook_split_view (Scratch.Widgets.SplitView view) {
        this.tool_button.visible = ! view.is_empty ();
        view.welcome_shown.connect (() => {
            this.tool_button.visible = false;
        });
        view.welcome_hidden.connect (() => {
            this.tool_button.visible = true;
        });
    }

    void on_hook_toolbar (Scratch.Widgets.Toolbar toolbar) {
        var icon = new Gtk.Image.from_icon_name ("utilities-terminal", Gtk.IconSize.LARGE_TOOLBAR);
        tool_button = new Gtk.ToggleToolButton ();
        tool_button.set_icon_widget (icon);
        tool_button.set_active (false);
        tool_button.tooltip_text = _("Show Terminal");
        tool_button.toggled.connect (() => {
            if (this.tool_button.active) {
                tool_button.tooltip_text = _("Hide Terminal");
                if (settings.position == Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM) {
                    bottombar.set_current_page (bottombar.append_page (grid, new Gtk.Label (_("Terminal"))));
                } else {
                    contextbar.set_current_page (contextbar.append_page (grid, new Gtk.Label (_("Terminal"))));
                }
                terminal.grab_focus ();
            } else {
                tool_button.tooltip_text = _("Show Terminal");
                if (settings.position == Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM) {
                    bottombar.remove_page (bottombar.page_num (grid));
                } else {
                    contextbar.remove_page (contextbar.page_num (grid));
                }
                window.get_current_document ().focus ();
            }
        });

        tool_button.show_all ();

        toolbar.pack_end (tool_button);
    }

    public string get_shell_location () {
        int pid = (!) (this.child_pid);

        try {
            return GLib.FileUtils.read_link ("/proc/%d/cwd".printf (pid));
        } catch (GLib.FileError error) {
            warning ("An error occured while fetching the current dir of shell");
            return "";
        }
    }

    public void settings_changed () {
        if (settings.position == Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM)
            move_terminal_bottombar ();
        else
            move_terminal_contextbar ();
    }

    void on_hook_notebook () {
        this.settings = new Scratch.Plugins.TerminalViewer.Settings ();
        settings.changed.connect (settings_changed);
        this.terminal = new Vte.Terminal ();
        this.terminal.scrollback_lines = -1;

        // Set font, allow-bold, audible-bell, background, foreground, and palette of pantheon-terminal
        var schema_source = SettingsSchemaSource.get_default ();
        var terminal_schema = schema_source.lookup (SETTINGS_SCHEMA, true);
        if (terminal_schema != null) {
            update_terminal_settings (SETTINGS_SCHEMA);
        } else {
            var legacy_terminal_schema = schema_source.lookup (LEGACY_SETTINGS_SCHEMA, true);
            if (legacy_terminal_schema != null) {
                update_terminal_settings (LEGACY_SETTINGS_SCHEMA);
            }    
        }

        // Set terminal font
        if (font_name == "") {
            var system_settings = new GLib.Settings ("org.gnome.desktop.interface");
            font_name = system_settings.get_string ("monospace-font-name");
        }
        #if ! VTE291
        this.terminal.set_font_from_string (font_name);
        #else
        var fd = Pango.FontDescription.from_string (font_name);
        this.terminal.set_font (fd);
        #endif

        // Popup menu
        var menu = new Gtk.Menu ();

        // COPY
        Gtk.MenuItem copy = new Gtk.MenuItem.with_label (_("Copy"));
        copy.activate.connect (() => {
            terminal.copy_clipboard ();
        });
        menu.append (copy);

        // PASTE
        Gtk.MenuItem paste = new Gtk.MenuItem.with_label (_("Paste"));
        paste.activate.connect (() => {
            terminal.paste_clipboard ();
        });
        menu.append (paste);

        // SEPARATOR
        menu.append (new Gtk.SeparatorMenuItem ());

        // ON RIGHT
        location_right = new Gtk.RadioMenuItem.with_label (null, _("Terminal on Right"));
        location_right.toggled.connect (() => {
            if (settings.position != Scratch.Plugins.TerminalViewer.TerminalPosition.RIGHT)
                settings.position = Scratch.Plugins.TerminalViewer.TerminalPosition.RIGHT;
        });
        menu.append (location_right);

        // ON BOTTOM
        location_bottom = new Gtk.RadioMenuItem.with_label (location_right.get_group (), _("Terminal on Bottom"));
        location_bottom.toggled.connect (() => {
            if (settings.position != Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM)
                settings.position = Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM;
        });
        menu.append (location_bottom);

        if (settings.position == Scratch.Plugins.TerminalViewer.TerminalPosition.BOTTOM)
            location_bottom.active = true;
        else
            location_right.active = true;

        menu.show_all ();

        this.terminal.button_press_event.connect ((event) => {
            if (event.button == 3) {
                menu.select_first (false);
                menu.popup (null, null, null, event.button, event.time);
            }
            return false;
        });

        try {
            string last_opened_path = settings.last_opened_path == "" ? "~/" : settings.last_opened_path;
            #if ! VTE291
            this.terminal.fork_command_full (Vte.PtyFlags.DEFAULT, last_opened_path, { Vte.get_user_shell () }, null, GLib.SpawnFlags.SEARCH_PATH, null, out child_pid);
            #else
            this.terminal.spawn_sync (Vte.PtyFlags.DEFAULT, last_opened_path, { Vte.get_user_shell () }, null, GLib.SpawnFlags.SEARCH_PATH, null, out child_pid);
            #endif
        } catch (GLib.Error e) {
            warning (e.message);
        }

        grid = new Gtk.Grid ();
        var sb = new Gtk.Scrollbar (Gtk.Orientation.VERTICAL, terminal.vadjustment);
        grid.attach (terminal, 0, 0, 1, 1);
        grid.attach (sb, 1, 0, 1, 1);

        // Make the terminal occupy the whole GUI
        terminal.vexpand = true;
        terminal.hexpand = true;

        grid.show_all ();
    }

    private void update_terminal_settings (string settings_schema) {
        var pantheon_terminal_settings = new GLib.Settings (settings_schema);

        font_name = pantheon_terminal_settings.get_string ("font");

        bool allow_bold_setting = pantheon_terminal_settings.get_boolean ("allow-bold");
        this.terminal.set_allow_bold (allow_bold_setting);

        bool audible_bell_setting = pantheon_terminal_settings.get_boolean ("audible-bell");
        this.terminal.set_audible_bell (audible_bell_setting);

        #if ! VTE291
        this.terminal.set_background_image (null); // allows background and foreground settings to take effect
        #endif

        string background_setting = pantheon_terminal_settings.get_string ("background");
        #if ! VTE291
        Gdk.Color background_color;
        Gdk.Color.parse (background_setting, out background_color);
        #else
        Gdk.RGBA background_color = Gdk.RGBA ();
        background_color.parse (background_setting);
        #endif

        string foreground_setting = pantheon_terminal_settings.get_string ("foreground");
        #if ! VTE291
        Gdk.Color foreground_color;
        Gdk.Color.parse (foreground_setting, out foreground_color);
        #else
        Gdk.RGBA foreground_color = Gdk.RGBA ();
        foreground_color.parse (foreground_setting);
        #endif

        string palette_setting = pantheon_terminal_settings.get_string ("palette");

        string[] hex_palette = {"#000000", "#FF6C60", "#A8FF60", "#FFFFCC", "#96CBFE",
                                "#FF73FE", "#C6C5FE", "#EEEEEE", "#000000", "#FF6C60",
                                "#A8FF60", "#FFFFB6", "#96CBFE", "#FF73FE", "#C6C5FE",
                                "#EEEEEE"};

        string current_string = "";
        int current_color = 0;
        for (var i = 0; i < palette_setting.length; i++) {
            if (palette_setting[i] == ':') {
                hex_palette[current_color] = current_string;
                current_string = "";
                current_color++;
            } else {
                current_string += palette_setting[i].to_string ();
            }
        }

        #if ! VTE291
        Gdk.Color[] palette = new Gdk.Color[16];
        #else
        Gdk.RGBA[] palette = new Gdk.RGBA[16];
        #endif

        for (int i = 0; i < hex_palette.length; i++) {
            #if ! VTE291
            Gdk.Color new_color;
            Gdk.Color.parse (hex_palette[i], out new_color);
            #else
            Gdk.RGBA new_color = Gdk.RGBA ();
            new_color.parse (hex_palette[i]);
            #endif

            palette[i] = new_color;
        }

        this.terminal.set_colors (foreground_color, background_color, palette);
    }
}

[ModuleInit]
public void peas_register_types (GLib.TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (Peas.Activatable),
                                     typeof (Scratch.Plugins.Terminal));
}
