# Colander

Colander makes Atom and RSS feeds from web pages and other feeds. Rules say
what to extract from a page, how to change it and which entries to keep.
This repository provides `colander`, a command-line utility written in the
[Wattle][] programming language.

[Wattle]: https://github.com/pyrmont/wattle

Colander replaces [Feedstock][], a Ruby library. It is in development and
does not make feeds yet.

[Feedstock]: https://github.com/pyrmont/feedstock

## Building

To build the `colander` binary from source, you need [Zig][] 0.17.1 and
Wattle, installed with the `<prefix>/share/wattle` support files. `-p` gives
the Wattle install prefix, or set `WATTLE_PREFIX` instead:

[Zig]: https://ziglang.org

```console
$ git clone https://github.com/pyrmont/colander
$ cd colander
$ wattle -p ~/.local build exe --release fast
```

The executable is at `zig-out/bin/colander`. It includes the Wattle runtime,
so the target system does not need Wattle to be installed. To build a static
executable for a Linux server:

```console
$ wattle -p ~/.local build exe --release fast -t x86_64-linux-musl
```

## Using

```
Usage: colander [--rules-dir <dir>] [--output-dir <dir>] [--stdout] [--include <name>] [--exclude <name>]

Make Atom and RSS feeds from web pages and other feeds.

Options:

 -r, --rules-dir <dir>     The directory of rules files. (Default: rules)
 -o, --output-dir <dir>    The directory to write feeds to. (Default: outputs)
 -O, --stdout              Write feeds to standard output instead.

 -i, --include <name>      Make only this feed. Can be given more than once.
 -e, --exclude <name>      Make every feed except this one. Can be given more than once.

 -v, --version             Show version information.

 -h, --help                Show this help message.
```

## Licence

Colander is licensed under the MIT Licence. See [LICENSE][] for more details.

[LICENSE]: LICENSE
