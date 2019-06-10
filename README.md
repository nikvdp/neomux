# Neomux

Everything awesome about tmux, but in neovim. 


# Installation

1. Install neovim. 
2. Install this plugin into neovim via your favorite plugin manager
   ([vim-plug][vim-plug] is a good place to start)
3. (Optional, for speed) install [neovim-remote][neovim-remote].


# Usage

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
identifier in it's status bar that looks like this: `∥ W:1 ∥`.

This number identifies every window on the screen and is how you refer to
individual windows in neomux.

Neomux adds new mappings to work with windows (They are accessed via the 
`<Leader>` key, which is `\` on a vanilla neovim install):

- `<Leader>w[1-9]` - move the cursor directly to the window specified (e.g.
  `<Leader>w3` wouldmove the cursor to window 3)
- `<Leader>s[1-9]` - swap the current window with another window. (e.g. `<Leader>s3` would make your current window switch places with whatever is in window #3)
- `<C-s>` - Exit insert mode while in a neomux shell. This is just an alias for
  `<C-\><C-n>` which is the default keymap to end insert mode.

## CLI helpers

You can start a neomux shell in a neovim window with the usual `:term` or with
the mapping `<Leader>sh`.

> **NOTE:**
>
> Neomux will automatically tell the shell to use your current neovim session as
> the default editor via the `$EDITOR` shell variable. This means that tools like
> `git` and `kubectl` will open files in your existing neovim session. Make sure you 
> use neovim's `:bd` (buffer delete) command when you are finished editing your
> files to notify the calling program you are done -- this is equivalent to
> closing a non-neomux editor. 

When you start a neomux shell some new helper commands will be available to you
to streamline working with neovim.

The most commonly used ones are: `vw` (vim window), `vp` (vim paste) and `vc` (vim copy).


- `vw <win_num> <file>` - open `<file>` in a vim window. For example:

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
[neovim-remote]: https://github.com/mhinz/neovim-remote

