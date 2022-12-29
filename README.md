# Neomux, control Neovim from shells running inside Neovim.

Neomux packages and wraps [neovim-remote][neovim-remote] goodness into your
neovim terminals so you can work with neovim's `:term` emulator in some
interesting new ways. Here's some of the things it lets you do:

- Pipe commands from the shell into a neovim window (and back to the shell) via stdin/stdout
- Easily jump to any neovim windows with 3 keystrokes, even when you have lots of
  splits and windows in-between (no more <C-w>l<C-w>l<C-w>l to get to the 3rd
  window on the right)
- Get and set the contents of vim registers from the command line via stdin/stdout.


<p align="center">
  <img width="75%" src="https://nikvdp.com/images/neomux-2-window-numbers.gif">
</p>


# Quickstart

Install neomux, start a neomux shell with `:Neomux` (mapped to `<Leader>sh` by
default), and use `vw <win_num> <file>` and friends to open files in vim
windows from the shell.

For more info see the [tutorial](#tutorial).

# Installation

1. Install neovim. 
2. Install this plugin into neovim via your favorite plugin manager
   ([vim-plug][vim-plug] is a good place to start)
3. (Optional, for speed) install [neovim-remote][neovim-remote].


# Usage

Neomux is meant to replace tools like tmux -- instead of relying on tmux or a
fancy tabbed terminal emulator to run multiple shell windows (many of which, if
you're anything like me, have instances of nvim running inside of them) you can
instead just have one neovim session open and run your shells inside neovim.
Vim has great tab and window splitting support, so you can rely on (neo)vim's
mature window and tab management workflow to make flipping between the files
you're editing and your shell(s) painless. Files and shells are both
first-class citizens, and all the tools you need to pass data between neovim
and your shell are included.

## Basics 
You can start a neomux shell in a neovim window with `:Neomux` or with
the mapping `<Leader>sh`.

**Terminals started via other methods (e.g. `:term`) will not have neomux functionality!**

> **NOTE:**
>
> Neomux will automatically tell the shell to use your current neovim session as
> the default editor via the `$EDITOR` shell variable. This means that tools like
> `git` and `kubectl` will open files in your existing neovim session. Make sure you 
> use neovim's `:bd` (buffer delete) command when you are finished editing your
> files to notify the calling program you are done -- this is equivalent to
> closing a non-neomux editor. 



## Window navigation

After installing neovim you will notice that every window in vim now shows a numeric
identifier in it's status bar that looks like this: 

``` 
∥ W:1 ∥
```

This number identifies every window on the screen and is how you refer to
individual windows in neomux.

## Key bindings

Neomux adds some new key mappings to make working with windows easier.  The
default keybindings can be customized from your `vimrc` / `init.vim`, see
[customization](#customization) for more info. 

In the default settings some commands are accessed via the `<Leader>` key (`\`
on a vanilla neovim install):

- `<Leader>sh` - Start a new neomux term in the current window.
- `<C-w>t` - Start a new neomux term above the current window (`:split`)
- `<C-w>T` - Start a new neomux term to the left of the current window (`:vsplit`)
- `<C-w>[1-9]` - move the cursor directly to the window specified (e.g.
  `<C-w>3` would move the cursor to window 3)
- `<Leader>s[1-9]` - swap the current window with another window. (e.g.
  `<Leader>s3` would make your current window switch places with window #3)
- `<C-s>` - Exit insert mode while in a neomux shell. This is just an alias for
  `<C-\><C-n>` which is the default keymap to end terminal insert mode.
- `<Leader>sf` - size-fix. If you re-arrange windows neovim's terminal
  sometimes doesn't automatically resize the terminal to match the new window's
  size. This keymapping will cause the window to refresh and resize.
- `<Leader>by` - yank buffer. Sometimes it's handy to be able to yank a buffer
  and paste it into a new window (I often use this if I want to move a window
  to a new tab). Yanked buffers can be pasted with `<Leader>bp`.
- `<Leader>bp` - paste a previously yanked buffer into a window.

# Tutorial

An extended version of this tutorial is available in the [introducing
neomux][neomux-blog-post] blog post.  All neomux terminals come pre-loaded with
some handy new shell commands.

### Opening files in new windows: `s`, `vs`, and (kind of) `t`


<p align="center">
  <img width="75%" src="https://nikvdp.com/images/neomux-1-new-windows.gif">
</p>

The simplest of the new neomux shell commands are `s`, `vs` and `t`. These
stand for `s`plit, `v`ertical-`s`plit, and `t`ab, and are straightforward to use.

If you have a neomux shell open and wanted to open a file you were looking at 
in a *new* window, you would simply do:

``` sh
s <some-file>
```

Similarly, `vs <some-file>`, and `t <some-file>` would open `<some-file>` in 
a vertical split, or a new tab, respectively.


### Working with windows by window-number: `vw` and `vwp`

<p align="center">
  <img width="75%" src="https://nikvdp.com/images/neomux-2-window-numbers.gif">
</p>

<!--
<div style="text-align: center;"> <script id="asciicast-251096" src="https://asciinema.org/a/251096.js" async></script> </div>
-->


One of the most commonly used neomux commands is `vw` (vim-window), it allows
you to open a file in an *already open* window.

For example if you have 3 windows open in your current nvim session/tab and you 
wanted to open a file named `my-file.txt` in the 2nd window you'd do:

``` sh
vw 2 my-file.txt
```

You can also use pass `-` as the filename to stream the contents of `stdin`
into a vim-window, which when combined with the shell's `|` characters makes
for some interesting possibilities. 

The `vwp` (vim-window-print) command does the reverse of the `vw` command. It
takes the contents of any vim window and streams it out to standard out. When
you combine this with your shell's [process substition][process-substition]
functionality, you can do some interesting things such as interactively working
on a bash script without having to first write it to a file. Check out vid above
for more details

### Copying/yanking and pasting text to and from neomux
<p align="center">
  <img width="75%" src="https://nikvdp.com/images/neomux-3-registers.gif">
</p>


Neomux comes with two helpers for working with vim's registers to copy and paste
text: `vc` and `vp`, which stand for vim-copy and vim-paste respectively.

With these, you can manipulate the contents of vim's yank ring and registers
from the command line. If you're not familiar with vim's register system, I
recommend first checking out [vim's documentation on the
topic][vim-registers-docs] and/or [this tutorial][vim-registers-tut].

Both `vc` and `vp`, work on the default register (`@"`) if no register is
specified.  To work with a specific register just pass it as the first cmd-line
param. For example, to work with register `a` (`@a`), you would use `vw a`, and
`vp a`. 

To put data in a register pipe it in via stdin:

``` sh
$ echo "This is what's in register a." | vc a
```

And get it out with `vp`:

``` sh
$ vp a
This is what's in register a. 
```

All vim register semantics are preserved, so you can append to the contents of a 
register by capitalizing the register name:

``` sh
$ echo " Appended to register a." | vc A
$ vp a
This is what's in register a. Appended to register a.
```

Special registers such as `/` and `+` work just like any other register, so
you could even use these as a roundabout way to replace `pbpaste` / `xsel` by
using `vp +` (although this is silly since at the end of the day neovim will
probably call those same tools to retrieve the clipboard). 

# CLI helper reference

When you start a neomux shell some new helper commands will be available to you
to streamline working with neovim.


- ### `vw <win_num> <file>` 

  Open `<file>` in vim window number `<win_num>`, where `<win_num>` is a number
  between 1 and 9. For example:

  ``` bash
  vw 2 ~/.config/nvim/init.vim 
  ```

  Would open your neovim config in window 2.

  You can also pipe shell commands into neovim windows by using `-` as the
  filename. The below command would fill window 2 with the list of files in the
  shell's working directory:

  ``` bash
  ls | vw 2 -
  ```
- ### `vc [register]` 
  copy data into a vim register (`@"` if no register specified). Example:

  ``` bash
  ls | vc a
  ```

  Would put the listing of files in the shell's working directory into vim register `a`, 
  which you could then paste in vim by doing e.g. `"aP`

- ### `vp [register]`
  paste data from a vim register (`@"` if no register specified).
- ### `e <file>`
  Open  `<file>`  in current window.
- ### `s <file>`
  Open `<file>` in a horizontal split.
- ### `vs <file>`
  Open `<file>` in a vertical split.
- ### `t <file>`
  Open `<file>` in a new tab.
- ### `vcd <path>`
  Switch neovim's working dir to `<path>`.
- ### `vpwd`
  Print neovim's working dir.  Useful with `cd "$(vpwd)"` to move the shell to
  neovim's current working dir.


<!--
# Cookbook

- A useful pattern is to combine `vw`, `vp`, and `xargs` to do
  operations over sets of files. For example, if you wanted to delete all files in a folder 
  except for file `b`, you could do:

  ``` bash
  ls | vw 2 -
  ...edit the file list in nvim and delete `b`...
  ...select all files and yank to the `@"` register with `ggVGy`...
  vp | xargs rm  # 
  ```
-->


# Customization

Neomux comes with a sane set of defaults, but it's meant to get out of your
way, so much of it's behavior is configurable. 

Configure neomux by setting any of these variables in your `.vimrc` / `init.vim`:


### Key bindings: 

- `g:neomux_start_term_map` - Default: `<Leader>sh`. This map controls what
  keys start a new Neomux term in the current window.
- `g:neomux_start_term_split_map` - Default: `<C-w>t`. This map controls what
  keys start a Neomux term in a `:split` window.
- `g:neomux_start_term_vsplit_map` - Default: `<C-w>T`. This map controls what keys
  start a Neomux term in a `:vsplit` window.
- `g:neomux_winjump_map_prefix` - Default: `<C-w>`. In Neomux you
  can jump to any open window by hitting `<C-w><win_num>` (e.g. `<C-w>2` jumps to
  window 2. Change this if you want to jump to a different window with a
  different mapping. 
  
  > **NOTE:** this is a prefix map, so whatever key you specify will
  > have 9 new mappings generated, one for each window. E.g. if you change this to
  > `<C-b>`, you would hit `<C-b>2` to move to window 2.
- `g:neomux_winswap_map_prefix` -  Default: `<Leader>s`. You can swap
  the current window with any other window by hitting `<Leader>s<win_num>`.
  Change this if you don't want to use `<Leader>s` for this map.

  > **NOTE:** like `g:neomux_winjump_map_prefix`, this is a prefix map, so if you change it to
  > `<Leader>b` it would create 9 new mappings, and you'd swap the current window
  > with window #2 with `<Leader>b2`.
- `g:neomux_yank_buffer_map` - Default: `<Leader>by`. Yank a buffer to be pasted later.
- `g:neomux_paste_buffer_map` - Default: `<Leader>bp`. Paste a previously yanked buffer into the current window.
- `g:neomux_term_sizefix_map` - Default: `<Leader>sf`. Fix a neomux term window that is the wrong size
- `g:neomux_exit_term_mode_map` - Default: `<C-s>`. Get out of insert mode when inside a neomux terminal window.

### Other config

- `g:neomux_default_shell` - Default: the value of your system's `$SHELL` env
  var. Neomux starts with the default shell for your user, but if you want to
  override this to force Neomux terminals to run bash/zsh/your-preferred-shell,
  set this var in your `.vimrc`/`init.vim`. E.g., if you want Neomux shells to
  start zsh, you would put `let g:neomux_default_shell = "zsh"` in your
  `init.vim`.
- `g:neomux_win_num_status` - Default: `∥ W:[%{WindowNumber()}] ∥`. By default
  Neomux adds decorations that look like `∥ W:1 ∥` to each window. If you'd like
  to customize this, set this variable to a different value. `%{WindowNumber()}`
  will be replaced by the window number itself. 

  If you have [airline](https://github.com/vim-airline/vim-airline) installed
  neomux will attempt to add it to your airline. If this doesn't work for you
  please leave an issue! **However, be sure to configure your plugin manager to
  load neomux *after* the airline plugin.**

- `g:neomux_dont_fix_term_ctrlw_map` - By default you can't get out of a neovim
  terminal window with `<C-w>` the way you can from a normal vim window. Neomux
  modifies the default mappings so that `<C-w>` works the same way in a terminal
  window as it does a normal window. Neomux includes a `NeomuxSendCtrlW()` helper
  function which you can use to send `<C-w>` to a terminal (`:call
  NeomuxSendCtrlW()`), however if you find yourself needing to use `<C-w>` often,
  you can restore neovim's default settings by setting
  `g:neomux_dont_fix_term_ctrlw_map` to `1`.

- `g:neomux_no_exit_term_map` - By default neomux adds a new mapping
  (`g:neomux_exit_term_mode_map`) to easily exit insert mode in a terminal
  window. If you don't want this mapping to be set at all and would like to use
  neovim's default `<C-\><C-n>`, you can disable it by setting
  `g:neomux_no_exit_term_map` to `1`.

### Miscellanea / troubleshooting

- If you want a simple way to send keys to a neomux terminal session you can do
  so via the `NeomuxSend(keys)` function. 

- Neomux relies heavily on the excellent [neovim-remote][neovim-remote], and
  includes amd64 binaries for neovim-remote for MacOS and Linux as they are the
  most popular platforms. If you're on Windows or using another chipset (e.g.
  Raspberry pi/ARM) you will need to install python and `pip` manually, and
  then install neovim-remote via `pip install neovim-remote` before neomux will
  work.


[vim-plug]: https://github.com/junegunn/vim-plug 
[tmux]: https://github.com/tmux/tmux
[neovim-remote]: https://github.com/mhinz/neovim-remote
[vim-registers-docs]: http://vimdoc.sourceforge.net/htmldoc/change.html#registers
[vim-registers-tut]: https://www.brianstorti.com/vim-registers/
[neovim]: https://neovim.io
[process-substition]: https://en.wikipedia.org/wiki/Process_substitution
[neomux-blog-post]: https://nikvdp.com/post/neomux
