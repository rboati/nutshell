# `nutshell` - Local shell initialization based on current directory

`nutshell` is a simple tool for switching environment automatically during command line work.

Here with enviroment we mean a shell initialized specifically for the set of operations to be done in a particular directory and its sub-directories, for example a node project or a rails project.

It's similar to [`direnv`](https://direnv.net/) but it chooses a different strategy for the same task by creating a nested shell for every environment.

It's written in bash and currently it's for bash only but it shouldn't be much difficult to port to other shells.


## Getting Started

Download the repository or clone it in a directory of your choice (for example `~/.local/lib/nutshell`).

Then just include this line in your `~/.bashrc`:
```sh
source "$HOME/.local/lib/nutshell/nutshell.bash"
```
Or if you want to try out the custom prompt which will give you a visual information of the environment you are currently in:
```sh
source "$HOME/.local/lib/nutshell/nutshell.bash" prompt
```

From now on in your shell whenever your current directory contains a file named `.nutsh` a new shell will be opened inside the current and sourceing the file `.nutsh`.

If you don't like to be notified whenever an environment is created or destroyed, you can also add `quiet` parameter


### Security

Before a `.nutsh` file can be sourced it needs to satisfy some requirements:
- it must be writable only by the owner
- it must be explicitly added to the list of trusted file  with `nutshell trust`
- its mtime record must not have changed since the last time it was trusted

## Usage

`nutshell` implements its functionality thorough a shell prompt hook that take care of opening and closing environments and a `nutshell` command line utility:

```
nutshell [command]
Available commands:
  init [template]  Initialize current directory with a default .nutsh file
                   or one specified by template name
  status           Show nutshell nesting status
  trust [dir]      Trust current directory or "dir" if specified
  untrust [dir]    Untrust current directory or "dir" if specified
  show             Print trusted directory list
  reload           Trust $NUTSHELL_DIR/.nutsh file and reload current nutshell
```

`nutshell init [template]` copies default `.nutsh` or one specified by template name from directory `~/.config/nutshell/templates/` into current directory, then the directory is trusted and a new nutshell shell is opened. You can modify the default template or create your own templates.

`nutshell status` prints intormations of the actual shell nesting.

`nutshell trust [dir]` tries to add current directory or specified directory to the list of trusted directories stored in `~/.config/nutshell/trustbd`. Directory must contains a `.nutsh` file.

`nutshell untrust [dir]` tries to remove current directory or specified directory from the list of trusted directories stored in `~/.config/nutshell/trustbd`.

`nutshell show` prints the list of trusted directories stored in `~/.config/nutshell/trustbd`.

`nutshell reload` restart current shell, trusting the directory of current `.nutsh` if necessary.

Changing directory outside the current environment automatically triggers the closing of its shell.

You can quit current environment also with `exit` command or pressing `CTRL-D`, in which case your next current directory will be set to the parent directory of the environment.

Note that environments can be nested, `nutshell` will take care of opening and closing only the right environments.

The current environment is uniquely identified by the directory absolute path containing the last `.nutsh` was sourced. This path is saved inside the readonly environment variable `NUTSHELL_DIR`.


## Authors

* **Roberto Boati** - *Initial work* - (https://github.com/rboati)


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details

## Acknowledgments

* Inspired by [`direnv`](https://direnv.net/)
