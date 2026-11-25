#!/usr/bin/perl
# Perl 5

# AtomicSync — Precision Synced, Atom by Atom — Single-Threaded (v5.2.1)
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
#   time-legacy                 # executes xterm and runs display inside it
#   time-legacy --loop          # run display loop in the current console
#   time-legacy --loop --once   # print one single frame then exit (for debugging)
#
# Keys: q / Q / Esc / Ctrl-C to quit.

# Requires: Time::HiRes (core), IO::Select (core), Term::ReadKey

use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_REALTIME CLOCK_MONOTONIC);
use IO::Select;
use Term::ReadKey;
use Cwd qw(abs_path);

$| = 1;

my $LOG_FILE  = "$ENV{HOME}/Blackbox-hwm/atomicsync.log";
my $PERIOD    = 0.05;   # 20 Hz redraw
my $LOG_EVERY = 60;     # re-read last-sync line every 60s
my $BANNER    = "AtomicSync — Precision Synced, Atom by Atom (Single-Threaded)";

my ($loop, $once) = (0, 0);
for my $arg (@ARGV) {
    $loop = 1 if $arg eq '--loop';
    $once = 1 if $arg eq '--once';
}

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

# one-shot mode: single frame, then exit (for debugging)
if ($once) {
    print render_frame_once(snapshot(), last_sync_summary());
    exit 0;
}

# terminal console setup & guaranteed cleanup
my $in_tui = 0;
sub restore_terminal {
    return unless $in_tui;
    $in_tui = 0;
    ReadMode('normal');
    print "\e[?25h\e[?1049l";
}

END { restore_terminal(); }

my $sig_caught = 0;
$SIG{INT}  = sub { $sig_caught = 1; };
$SIG{TERM} = $SIG{INT};

print "\e[?1049h\e[?25l\e[2J\e[H";
ReadMode('cbreak');
$in_tui = 1;

my $sel = IO::Select->new(\*STDIN);

my $last_sync   = last_sync_summary();
my $now_mono    = clock_gettime(CLOCK_MONOTONIC);
my $next_log_at = $now_mono + $LOG_EVERY;
my $next_frame  = $now_mono;
my $first       = 1;

while (!$sig_caught) {
    my $mono = clock_gettime(CLOCK_MONOTONIC);

    if ($mono >= $next_log_at) {
        $last_sync   = last_sync_summary();
        $next_log_at = $mono + $LOG_EVERY;
    }

    render_frame(snapshot(), $last_sync, \$first);

    $next_frame += $PERIOD;
    my $s = $next_frame - clock_gettime(CLOCK_MONOTONIC);
    if ($s < 0) {
        $next_frame = clock_gettime(CLOCK_MONOTONIC);
        $s = 0;
    }

    # Wait up to $s seconds for input; wakes immediately on keypress or signal
    if ($sel->can_read($s)) {
        my $n = sysread(STDIN, my $ch, 1);
        last if !$n || $ch eq 'q' || $ch eq 'Q' || $ch eq "\e";
    }
}

restore_terminal();
exit 0;

# helpers

sub snapshot {
    my $t    = clock_gettime(CLOCK_REALTIME);
    my $sec  = int($t);
    my $ns   = int(($t - $sec) * 1_000_000_000);
    $ns = 999_999_999 if $ns >= 1_000_000_000;
    my ($s, $m, $h) = (localtime($sec))[0, 1, 2];
    return {
        t   => $t,
        sec => $sec,
        ns  => $ns,
        h   => $h,
        m   => $m,
        s   => $s,
    };
}

sub to_binary { sprintf '%06b', $_[0] & 0x3f }

sub render_frame_once {
    my ($snap, $sync) = @_;
    my $b = to_binary($snap->{h}) . ' : '
          . to_binary($snap->{m}) . ' : '
          . to_binary($snap->{s});

    return sprintf(
        "%s\n\n\n" .
        "Precision:\n  %02d:%02d:%02d.%09d\n\n" .
        "Unix:\n  %d\n\n" .
        "Binary:\n  %s\n\n" .
        "Last sync:\n  %s\n\n",
        $BANNER,
        $snap->{h}, $snap->{m}, $snap->{s}, $snap->{ns},
        $snap->{sec},
        $b,
        $sync,
    );
}

sub render_frame {
    my ($snap, $sync, $first_ref) = @_;
    my $b = to_binary($snap->{h}) . ' : '
          . to_binary($snap->{m}) . ' : '
          . to_binary($snap->{s});

    if ($$first_ref) {
        $$first_ref = 0;
        print "\e[H\e[2J";
        printf "\e[1;1H%s",  $BANNER;
        printf "\e[4;1H%s",  "Precision:";
        printf "\e[7;1H%s",  "Unix:";
        printf "\e[10;1H%s", "Binary:";
        printf "\e[13;1H%s", "Last sync:";
    }

    printf "\e[5;3H  %02d:%02d:%02d.%09d\e[K",
        $snap->{h}, $snap->{m}, $snap->{s}, $snap->{ns};
    printf "\e[8;3H  %d\e[K", $snap->{sec};
    printf "\e[11;3H  %s\e[K", $b;
    printf "\e[14;3H  %s\e[K", $sync;
}

sub last_sync_summary {
    my $fallback = '(no successful sync found in log)';
    return $fallback unless -r $LOG_FILE;

    open my $fh, '<', $LOG_FILE or return "(cannot read log: $!)";
    my @lines = <$fh>;
    close $fh;

    my ($success_idx, $success_line) = (-1, undef);
    for (my $i = $#lines; $i >= 0; $i--) {
        if ($lines[$i] =~ /AtomicSync successful/) {
            ($success_idx, $success_line) = ($i, $lines[$i]);
            last;
        }
    }
    return $fallback if $success_idx < 0;

    my $detail;
    for (my $j = $success_idx - 1; $j >= 0 && $j >= $success_idx - 5; $j--) {
        if ($lines[$j] =~ m{
                ^(\d{4}-\d{2}-\d{2}\ \d{2}:\d{2}:\d{2}\.\d+)\s+
                \((-?\d+)\)\s+
                ([+-]\d+\.\d+)\s+
                [+-]\/[+-]\s*(\d+\.\d+)\s+
                (\S+)\s+(\S+)\s+(s\d+)\s+\S+
            }x) {
            my ($ts, $srv_stratum, $offset, $bound, $server, $ip, $stratum) =
                ($1, $2, $3, $4, $5, $6, $7);
            $detail = sprintf('%s  offset %s s  +/-%s s  %s (%s, %s)',
                $ts, $offset, $bound, $server, $ip, $stratum);
            last;
        }
    }

    unless (defined $detail) {
        my $s = $success_line;
        $s =~ s/^\s+//;
        $s =~ s/\s+$//;
        my $i = index($s, '[');
        $s = substr($s, $i) if $i >= 0;
        $detail = $s;
    }

    return $detail;
}
