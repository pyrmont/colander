# Colander

[![Latest Release][release-badge]][release-latest]
[![Test Status][test-badge]][test-status]

[release-badge]: https://img.shields.io/github/v/release/pyrmont/colander
[release-latest]: https://github.com/pyrmont/colander/releases/latest
[test-badge]: https://github.com/pyrmont/colander/actions/workflows/test.yml/badge.svg
[test-status]: https://github.com/pyrmont/colander/actions/workflows/test.yml

Colander makes Atom and RSS feeds from web pages and other feeds. Rules say
what to extract from a page, how to change it and which entries to keep.
This repository provides `colander`, a command-line utility written in the
[Wattle][] programming language.

[Wattle]: https://github.com/pyrmont/wattle

Colander replaces [Feedstock][], a Ruby library.

[Feedstock]: https://github.com/pyrmont/feedstock

## Building

#### Pre-Built

Pre-built binaries of `colander` are available as tarballs via the
[Releases][github-releases] section on GitHub for:

- Linux (x86-64 and aarch64, statically linked)
- macOS (aarch64)

[github-releases]: https://github.com/pyrmont/colander/releases

```console
$ curl -LO https://github.com/pyrmont/colander/releases/latest/download/colander-<version>-<platform>-<arch>.tar.gz
$ tar -xzf colander-<version>-<platform>-<arch>.tar.gz
$ cd colander-<version>
```

Each tarball holds the binary and the man page.

#### From Source

To build the `colander` binary from source, you need [Zig][] 0.17.1 and
Wattle, installed with the `<prefix>/share/wattle` support files. `-p` gives
the Wattle install prefix, or set `WATTLE_PREFIX` instead:

[Zig]: https://ziglang.org

```console
$ git clone https://github.com/pyrmont/colander
$ cd colander
$ wattle -p ~/.local build exe --release fast
```

The executable is at `zig-out/bin/colander`. It includes the Wattle runtime
and the compiler that rules files need, so the target system does not need
Wattle to be installed. To build a static executable for a Linux server:

```console
$ wattle -p ~/.local build exe --release fast -t x86_64-linux-musl
```

## Installing

Move the `colander` binary somewhere on your path and the man page to the
appropriate location. For example:

```console
$ mkdir -p ~/bin ~/.local/share/man/man1
$ cp zig-out/bin/colander ~/bin/
$ cp man/man1/colander.1 ~/.local/share/man/man1/
```

If you have Wattle installed, you can instead build and install `colander`
and its man page under your `WATTLE_PREFIX` in one step:

```console
$ wattle apps install https://github.com/pyrmont/colander
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

See [`colander(1)`][colander-man] for the full reference (`man colander`).

[colander-man]: man/man1/colander.1.predoc

### Writing Rules

Each feed is a rules file, `<rules-dir>/<name>.wattle`, and is written to
`<output-dir>/<name>.xml`. A rules file is a Wattle program that defines
`feed`, a map:

```clojure
(def- url "https://example.org/essays.html")

(def- link (extract "a" :attr "href" :prefix "https://example.org"))

(def feed
  {:url url
   :info [[:id url]
          [:updated (header "Last-Modified" :type :datetime)]
          [:title "Essays"]
          [:author "A. Writer"]]
   :entries (extract "ul.posts > li")
   :entry [[:id link]
           [:title (extract "a")]
           [:link link]]})
```

`:entries` selects each entry's element, and the rules in `:entry` select
within it. `extract` takes a CSS selector and options that say what to take
from the element (`:attr`, `:content`), how to change it (`:process`,
`:prefix`, `:suffix`) and how to write it (`:type :datetime` or `:cdata`).
A feed can also give `:format :xml` to read another feed, `:template
:podcast` to write RSS for podcasts, and `:keep?` and `:transform` to filter
and change entries. The man page describes each of these.

A rules file is code, and Colander runs it. Use rules files that you have
written or read.

Colander writes each feed to a temporary file and renames it into place. A
feed that fails is reported on standard error and keeps its old file, and
the exit status is 1. To check a feed without writing it:

```console
$ colander -O -i essays
```

### Running from Cron

Colander makes every feed and exits, so run it from cron. For example, every
two hours:

```
0 */2 * * * cd /srv/feeds && $HOME/bin/colander -o public
```

### Moving from Feedstock

Feedstock was a Ruby library, used with a script that loaded a Ruby class
for each feed. To move to Colander:

1. Write a rules file for each class. Each `Feedstock::Extract.new(selector:
   s, ...)` becomes `(extract s ...)`, with `content: { attribute: "href" }`
   as `:attr "href"`, `content: "inner_html"` as `:content :inner-html`,
   `type: "datetime"` as `:type :datetime` and so on. The `info` and `entry`
   hashes become vectors of `[name value]` pairs, in the order to write
   them.
2. Split a `filter` lambda that also changed entries into `:keep?` and
   `:transform`.
3. Use `:template :podcast` in place of a `podcast.xml` ERB template, or
   give a function as `:template`.
4. Give `--include` and `--exclude` the feed's name, such as `six_colors`,
   rather than the path of its rules file.

Expect some differences in the feeds: Colander escapes Atom text, which
Feedstock did not, and writes `:type :datetime` dates as RFC 3339.

## Licence

Colander is licensed under the MIT Licence. See [LICENSE][] for more details.

[LICENSE]: LICENSE
