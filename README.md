# Neomux

Everything awesome about tmux, but in [neovim][neovim]. 


# Installation

1. Install neovim. 
2. Install this plugin into neovim via your favorite plugin manager
   ([vim-plug][vim-plug] is a good place to start)
3. (Optional, for speed) install [neovim-remote][neovim-remote].


# Usage

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

## Recommended workflow

Neomux is meant to replace tools like tmux -- instead of relying on tmux or a
fancy tabbed terminal emulator to run multiple shell windows (many of which, if
you're anything like me, have instances of nvim running inside of them) you can
instead just have one neovim session open and run your shells inside neovim.
Vim has great tab and window splitting support, so you can rely on (neo)vim's
mature window and tab management workflow to make flipping between the files
you're editing and your shell(s) painless. Files and shells are both
first-class citizens, and all the tools you need to pass data between neovim
and your shell are included.

## Window navigation

After installing neovim you will notice that every window in vim now shows a numeric
identifier in it's status bar that looks like this: 

``` 
∥ W:1 ∥
```

This number identifies every window on the screen and is how you refer to
individual windows in neomux.

Neomux adds new mappings to work with windows (They are accessed via the 
`<Leader>` key, which is `\` on a vanilla neovim install):

- `<Leader>w[1-9]` - move the cursor directly to the window specified (e.g.
  `<Leader>w3` wouldmove the cursor to window 3)
- `<Leader>s[1-9]` - swap the current window with another window. (e.g. `<Leader>s3` would make your current window switch places with whatever is in window #3)
- `<C-s>` - Exit insert mode while in a neomux shell. This is just an alias for
  `<C-\><C-n>` which is the default keymap to end insert mode.

## Tutorial

All neomux terminals come pre-loaded with some handy new shell commands.

### Opening files in new windows: `s`, `vs`, and (kind of) `t`


<p align="center">
<img width="75%" style="width: 400px; height: 400px;" src="https://srv.nikvdp.com/neomux/opening-files.gif">
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
<img width="75%" style="width: 400px; height: 400px;" src="https://srv.nikvdp.com/neomux/windows.svg">
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
<div style="text-align: center;"> <script id="asciicast-251108" src="https://asciinema.org/a/251108.js" async></script> </div>


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
you could even use these as a replacement for `pbpaste` / `xsel` by using `vp
+`. 

## CLI helpers

When you start a neomux shell some new helper commands will be available to you
to streamline working with neovim.

The most commonly used ones are: `vw` (vim window), `vp` (vim paste) and `vc` (vim copy).


- ### `vw <win_num> <file>` 

  Open `<file>` in a vim window. For example:

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
- `vc [register]` - copy data into a vim register (`@"` if no register specified). Example:

  ``` bash
  ls | vc a
  ```

  Would put the listing of files in the shell's working directory into vim register `a`, 
  which you could then paste in vim by doing e.g. `"aP`

- `vp [register]` - paste data from a vim register (`@"` if no register specified).
- `s <file>` - Open `<file>` in a horizontal split.
- `vs <file>` - Open `<file>` in a vertical split.
- `t <file>` - Open `<file>` in a new tab.
- `vcd <path>` - Switch neovim's working dir to `<path>`.
- `vpwd` - Print neovim's working dir. Useful with `cd "$(vpwd)"` to move the
  shell to neovim's current working dir.


## Cookbook

- A useful pattern is to combine `vw`, `vp`, and `xargs` to do
  operations over sets of files. For example, if you wanted to delete all files in a folder 
  except for file `b`, you could do:

  ``` bash
  ls | vw 2 -
  ...edit the file list in nvim and delete `b`...
  ...select all files and yank to the `@"` register with `ggVGy`...
  vp | xargs rm  # 
  ```


# Customization

Coming soon...

[vim-plug]: https://github.com/junegunn/vim-plug 
[tmux]: https://github.com/tmux/tmux
[neovim-remote]: https://github.com/mhinz/neovim-remote
[vim-registers-docs]: http://vimdoc.sourceforge.net/htmldoc/change.html#registers
[vim-registers-tut]: https://www.brianstorti.com/vim-registers/
[neovim]: https://neovim.io
[process-substition]: https://en.wikipedia.org/wiki/Process_substitution

