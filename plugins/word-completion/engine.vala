/*
 * Copyright (c) 2011 Lucas Baudin <xapantu@gmail.com>
 *
 * This is a free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; see the file COPYING.  If not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 */

public class Euclide.Completion.Parser : GLib.Object {
    public const int MINIMUM_WORD_LENGTH = 1;
    public const int MAX_TOKENS = 1000000;

    public const string delimiters = " .,;:?{}[]()0123456789+-=&|-<>*\\/\n\t\'\"";
    public bool is_delimiter (unichar c) {
        return delimiters.index_of_char (c) >= 0;
    }

    public Gee.HashMap<Gtk.TextView,Gee.ArrayList<string>> text_view_words;
    public bool parsing_cancelled = false;

    private Gee.ArrayList<string> words;
    private string last_word = "";

    public Parser () {
         text_view_words = new Gee.HashMap<Gtk.TextView,Gee.ArrayList<string>> ();
    }

    public void add_last_word () {
        add_word (last_word);
    }

    public bool get_for_word (string to_find, out Gee.TreeSet<string> list) {
        uint length = to_find.length;
        list = new Gee.TreeSet<string> ();
        last_word = to_find;
        if (words != null) {
            lock (words) {
                foreach (var word in words) {
                    if (word.length > length && word.slice (0, length) == to_find) {
                        list.add (word);
                    }
                }
            }
        }

        return !list.is_empty;
    }

    public void rebuild_word_list (Gtk.TextView view) {
        lock (words) {
            words.clear ();
        }
        parse_text_view (view);
    }

    public void parse_text_view (Gtk.TextView view) {
        /* If this view has already been parsed, restore the word list */
        lock (words) {
            if (text_view_words.has_key (view)) {
                words = text_view_words.@get (view);
            } else {
            /* Else create a new word list and parse the buffer text */
                words = new Gee.ArrayList<string> ();
            }
        }

        if (view.buffer.text.length > 0) {
            parse_string (view.buffer.text);
            text_view_words.@set (view, words);
        }
    }

    private void add_word (string word) {
        if (word.length < MINIMUM_WORD_LENGTH)
            return;

        if (!(word in words)) {
            lock (words) {
                words.add (word);
            }
        }
    }

    public void cancel_parsing () {
        parsing_cancelled = true;
    }

    private bool parse_string (string text) {
        parsing_cancelled = false;
        string [] word_array = text.split_set (delimiters, MAX_TOKENS);
        foreach (var current_word  in word_array ) {
            if (parsing_cancelled) {
                debug ("Cancelling parse");
                return false;
            }
            add_word (current_word);
        }
        return true;
    }
}
