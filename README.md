emacs-term-toggle
=================

Derived from Joseph <jixiuf@gmail.com> (URL:
http://www.emacswiki.org/term-toggle.el), this plugin brings up a
quake-style console with commands term-toggle{,-cd}. The major
difference with Joseph's version is that maximized console feature is
removed (in the original version sometimes it gets stuck in maximized
state, possibly because the window configuration is corrupted). Also,
this plugin determines whether to split a new window for the console,
or replace the buffer of current selected window if height is not
enough for a split. Another feature is that this plugin will detect
the status of the terminal. When there's no process running in
*terminal* buffer, it will fire up another one.

The major differences from Yatao's version is ability to open eshell console in
current buffers directory.

Added is also the option `term-toggle-no-confirm-exit' to let Emacs exit term
buffer and kill bash process without confirmation.

Installation:

git clone it, and setup instruction is in the source file.
