# Changelog

Each release lists what changed since the release before it. The changes made
since the most recent release are under Unreleased.

## 0.1.0 (2026-11-21)

The first release of Colander. It replaces Feedstock, a Ruby library (last
released as 0.4.0), and the script that ran it for feeds.inqk.net. The
differences from Feedstock are:

- Colander is a single executable, `colander`, with no Ruby dependencies. It
  makes a feed for each rules file in a directory, with the options of the
  feeds.inqk.net script: `--rules-dir`, `--output-dir`, `--stdout`,
  `--include` and `--exclude`. `--include` and `--exclude` take a feed's
  name rather than a path, cannot be used together, and refuse a name that
  has no rules file.
- Rules are Wattle files that define a `feed` map, in place of Ruby classes.
  `extract` takes the options of `Feedstock::Extract`, with `:attr` in place
  of `content: { attribute: ... }`. `header` takes the value of a response
  header, such as `Last-Modified`.
- An entry is kept with `:keep?` and changed with `:transform`, two
  functions in place of a filter that did both. `:keep?` runs first.
- Pages are parsed by a lenient HTML and XML parser written in Wattle, and
  selected with a subset of CSS. A selector outside the subset is an error.
  On the feeds of feeds.inqk.net, every field gave the same text as with
  Nokogiri.
- The Atom template escapes every text value; Feedstock's escaped none, so a
  title or URL with `&` made the feed invalid. A CDATA value in an Atom text
  construct, such as `content`, is marked `type="html"`.
- `:type :datetime` writes RFC 3339, keeping the source's offset, and reads
  RFC 822 and HTTP dates as well as the forms Feedstock read.
- The `:podcast` template, from feeds.inqk.net's `podcast.xml`, is built in.
  A rules file can also give its own template as a function.
- Each feed is written to a temporary file and renamed into place. A feed
  that fails is reported on standard error and keeps its old file, the
  others are still made, and the exit status is 1. A feed with no entries
  is written with a warning.
- Pages are fetched with a timeout (30 seconds by default), a limit on their
  size (16 MiB) and a User-Agent that names Colander.
- Added a man page, `colander(1)`.
