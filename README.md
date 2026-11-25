# AtomicSync

AtomicSync is a lightweight Perl utility that displays a live, atomically-synced
clock in your terminal console.

It reads the results of your existing `AtomicSync` sync log and renders precision 
time down to the nanosecond, alongside the Unix epoch and a binary representation 
of the current time.

Version 5.2.1 is a complete rewrite of the previous versions.

AtomicSync is now multi-threaded, opening up all CPU core threads for processing.

Some older hardware work better with single-threaded processing, therefore a 
single-threaded version is also provided.

- **`AtomicSync-NG.pl`** — multi-threaded (v5.2.1)
- **`AtomicSync-Legacy.pl`** — single-threaded (v5.2.1)

Both render the same display in the terminal console at 20 Hz.

The multi-threaded version isolates rendering from log polling so redraws are 
never stalled by disk I/O.

---

## AtomicSync features

- Live terminal console clock with nanosecond precision
- Unix epoch and binary (HH : MM : SS) representations
- Last-sync summary parsed from `atomicsync.log` (server, offset, uncertainty, stratum)
- 20 Hz redraw (50 ms period)
- Log re-read every 60 seconds without blocking the display
- Clean (and improved) terminal console restore on quit (`Q`, `Ctrl-C`, or `SIGTERM`)
- Launches inside `xterm` automatically when run without `--loop`
- Multi-threaded version reports frame/gap diagnostics with `--stats` argument
- Minimal dependencies (core Perl modules plus `Term::ReadKey`)

---

## How it works

1. On execution (without `--loop`) the script executes `xterm` and re-runs itself
   with `--loop` inside the new terminal console.
2. The render loop samples `CLOCK_REALTIME` and `CLOCK_MONOTONIC` via
   `Time::HiRes`, draws the banner, precision time, Unix epoch and binary time 
   representations, and a last-sync summary.
3. The last-sync summary is parsed from the most recent `AtomicSync successful`
   entry in `atomicsync.log`, scanning backwards up to five lines to recover the 
   detailed offset/uncertainty/server record.
4. In the multi-threaded version a dedicated log-reader thread refreshes the
   summary every 60 seconds while the render thread keeps (re)drawing at 20 Hz.

---

## Runtime & Packaging requirements

- GNU Operating System / H-Linux
- H-Linux Environment Library
- H-Linux Human Command Layer
- Hash
- Perl 5 (w/ `threads` and `threads::shared` for `AtomicSync-NG.pl`)
- PAR Packager (`perl-par-packer`)
- `Time::HiRes` (core)
- `IO::Select` (core)
- `Cwd` (core)
- `Term::ReadKey`
- `xterm` (for the default non-`--loop` launch mode)
- A populated `atomicsync.log` produced by the AtomicSync sync script

---

## Compile & Install procedures

### Clone the repository:

```bash
> gh repo clone https://www.github.com/fpucore/AtomicSync.git

> goto AtomicSync
```

### Install `perl-par-packer` (only if not already installed)

```bash
> boxforge install perl-par-packer
```

### Install `Term::ReadKey` (only if not already installed)

```bash
> cpan Term::ReadKey
```

### Compile

Multi-threaded version:

```bash
> pp -M threads -M threads::shared -M Term::ReadKey -M Time::HiRes -o AtomicSync-NG AtomicSync-NG.pl
```

Single-threaded version:

```bash
> pp -o AtomicSync-Legacy AtomicSync-Legacy.pl
```

### Install

Install the execution helper:

```bash
> copy cron/AtomicSync.hash $HOME/.hwm/AtomicSync
```

Multi-threaded version:

```bash
> elevate copy AtomicSync-NG /usr/local/bin/
```

Single-threaded version:

```bash
> elevate copy AtomicSync-Legacy /usr/local/bin/
```

### Add cron job

```bash
> crontab -e
```

Add the job execution string:
```bash
0 * * * * /home/foobar/.hwm/AtomicSync
```

*Remember to change `foobar` to your actual username.*

### Manually execute

```bash
> AtomicSync-NG
```

or

```bash
> AtomicSync-Legacy
```

---

## Example

```bash
AtomicSync — Precision Synced, Atom by Atom


Precision:
    09:51:07.508601427

Unix:
    1795564267

Binary:
    001001 : 110011 : 000111

Last sync:
    2026-11-25 09:00:03.918243  offset +0.044057 s  +/-0.029956 s  time.nist.gov (132.163.97.3, s1)
```

---

## Usage

Multi-threaded version:

```bash
> AtomicSync-NG                   # execute in xterm and run the display
> AtomicSync-NG --loop            # run display loop in the current terminal console
> AtomicSync-NG --loop --stats    # print frame/gap diagnostics on exit
```

Single-threaded version:

```bash
> AtomicSync-Legacy                  # execute in xterm and run the display
> AtomicSync-Legacy --loop           # run display loop in the current terminal console
> AtomicSync-Legacy --loop --once    # print one frame and exit
```

Keys: Q/q, ESC, or CTRL+C to quit the program.

---

## Log File

The display reads sync activity from the log file:

```bash
$HOME/Blackbox-hwm/atomicsync.log
```

---

## License

AtomicSync is released under the **MIT License**.
