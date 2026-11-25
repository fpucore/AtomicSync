#!/usr/bin/perl
# Perl 5

# AtomicSync — Precision Synced, Atom by Atom — Multi-Threaded (v5.2.1)
#
# Copyright (c) 2026 Chris McGimpsey-Jones <chrisjones.unixmen@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


# Usage:
#   time-ng                # executes xterm and runs display inside it
#   time-ng --loop         # run display loop in the current console
#   time-ng --loop --stats # print frame/gap diagnostics on exit
#
# Keys: q / Q / Esc / Ctrl-C to quit.
#
# Requires: threads, threads::shared, Time::HiRes, IO::Select, Term::ReadKey

use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(clock_gettime sleep CLOCK_REALTIME CLOCK_MONOTONIC);
use IO::Select;
use Term::ReadKey;
use Cwd qw(abs_path);

$| = 1;

my $LOG_FILE  = "$ENV{HOME}/Blackbox-hwm/atomicsync.log";
my $PERIOD    = 0.05;
my $LOG_EVERY = 60;
my $BANNER    = "AtomicSync — Precision Synced, Atom by Atom (Multi-Threaded)";

my $loop  = grep { $_ eq '--loop'  } @ARGV;
my $stats = grep { $_ eq '--stats' } @ARGV;

# non-loop mode: exec xterm and run the loop inside it
if (!$loop) {
    my $self = $ENV{PAR_PROGNAME} ? abs_path($ENV{PAR_PROGNAME}) : abs_path($0);
    $ENV{HOME}    //= '/home/chris';
    $ENV{DISPLAY} //= ':0';
    my @cmd = $ENV{PAR_PROGNAME}
        ? ('xterm', '-e', $self, '--loop')
        : ('xterm', '-e', $^X, $self, '--loop');
    exec @cmd;
    warn "Failed to launch xterm: $!\n";
    exit 1;
}

# terminal console setup & guaranteed main-thread cleanup
my $in_tui = 0;
sub restore_terminal {
    return unless $in_tui;
    $in_tui = 0;
    ReadMode('normal');
    print "\e[?25h\e[?1049l";
}

END {
    restore_terminal() if threads->tid() == 0;
}

# ---------- shared state ----------
my $quit      :shared = 0;
my $last_sync :shared = compute_last_sync();

my $sig_caught = 0;
$SIG{INT}  = sub { $sig_caught = 1; };
$SIG{TERM} = $SIG{INT};

# Keep all TTY mode changes and key reading on the main thread (tid 0)
print "\e[?1049h\e[?25l\e[2J\e[H";
ReadMode('cbreak');
$in_tui = 1;

my $sel = IO::Select->new(\*STDIN);

# ---------- render thread ----------
my $render_thr = threads->create({ context => 'list' }, sub {
    my $first   = 1;
    my $frames  = 0;
    my $max_gap = 0;
    my $next    = clock_gettime(CLOCK_MONOTONIC);
    my $last_m  = $next;

    RENDER: while (1) {
        { lock($quit); last RENDER if $quit; }

        my $mono = clock_gettime(CLOCK_MONOTONIC);
        my $gap  = $mono - $last_m;
        $max_gap = $gap if $frames > 0 && $gap > $max_gap;
        $last_m  = $mono;

        my $t   = clock_gettime(CLOCK_REALTIME);
        my $sec = int($t);
        my $ns  = int(($t - $sec) * 1_000_000_000);
        $ns = 999_999_999 if $ns >= 1_000_000_000;
        my ($s, $m, $h) = (localtime($sec))[0, 1, 2];

        if ($first) {
            $first = 0;
            print "\e[H\e[2J";
            printf "\e[1;1H%s",  $BANNER;
            printf "\e[4;1H%s",  "Precision:";
            printf "\e[7;1H%s",  "Unix:";
            printf "\e[10;1H%s", "Binary:";
            printf "\e[13;1H%s", "Last sync:";
        }

        my $sync;
        { lock($last_sync); $sync = $last_sync; }

        printf "\e[5;3H  %02d:%02d:%02d.%09d\e[K", $h, $m, $s, $ns;
        printf "\e[8;3H  %d\e[K", $sec;
        printf "\e[11;3H  %06b : %06b : %06b\e[K", $h, $m, $s;
        printf "\e[14;3H  %s\e[K", $sync;

        $frames++;

        $next += $PERIOD;
        my $sl = $next - clock_gettime(CLOCK_MONOTONIC);
        if ($sl > 0) {
            sleep($sl);
        } else {
            $next = clock_gettime(CLOCK_MONOTONIC);
        }
    }

    return ($frames, $max_gap);
});

# log-reader thread
my $log_thr = threads->create(sub {
    LOG: while (1) {
        {
            lock($quit);
            last LOG if $quit;
            cond_timedwait($quit, time() + $LOG_EVERY);
            last LOG if $quit;
        }

        my $summary = compute_last_sync();
        { lock($last_sync); $last_sync = $summary; }
    }
});

# main thread: read keys + supervise workers
while (1) {
    last if $sig_caught;
    last unless $render_thr->is_running() && $log_thr->is_running();

    if ($sel->can_read(0.05)) {
        my $n = sysread(STDIN, my $ch, 1);
        last if !$n || $ch eq 'q' || $ch eq 'Q' || $ch eq "\e";
    }
}

{
    lock($quit);
    $quit = 1;
    cond_broadcast($quit);
}

my ($f, $g) = $render_thr->join;
$log_thr->join;
restore_terminal();

for my $pair (['render', $render_thr], ['log', $log_thr]) {
    if (defined(my $err = $pair->[1]->error())) {
        warn "[$pair->[0] thread error] $err\n";
    }
}

if ($stats) {
    printf STDERR "[threaded] frames=%d  worst inter-frame gap=%.4fs\n",
        ($f // 0), ($g // 0);
}

# helpers

sub compute_last_sync {
    my $fallback = '(no successful sync found in log)';
    return $fallback unless -r $LOG_FILE;

    open my $fh, '<', $LOG_FILE or return "(cannot read log: $!)";
    my @lines = <$fh>;
    close $fh;

    my ($idx, $line) = (-1, undef);
    for (my $i = $#lines; $i >= 0; $i--) {
        if ($lines[$i] =~ /AtomicSync successful/) {
            ($idx, $line) = ($i, $lines[$i]);
            last;
        }
    }
    return $fallback if $idx < 0;

    my $detail;
    for (my $j = $idx - 1; $j >= 0 && $j >= $idx - 5; $j--) {
        if ($lines[$j] =~ m{
                ^(\d{4}-\d{2}-\d{2}\ \d{2}:\d{2}:\d{2}\.\d+)\s+
                \((-?\d+)\)\s+
                ([+-]\d+\.\d+)\s+
                [+-]\/[+-]\s*(\d+\.\d+)\s+
                (\S+)\s+(\S+)\s+(s\d+)\s+\S+
            }x) {
            my ($ts, $srv, $off, $bound, $server, $ip, $stratum) =
                ($1, $2, $3, $4, $5, $6, $7);
            $detail = sprintf('%s  offset %s s  +/-%s s  %s (%s, %s)',
                $ts, $off, $bound, $server, $ip, $stratum);
            last;
        }
    }
    unless (defined $detail) {
        my $s = $line;
        $s =~ s/^\s+//;
        $s =~ s/\s+$//;
        my $i = index($s, '[');
        $s = substr($s, $i) if $i >= 0;
        $detail = $s;
    }
    return $detail;
}
