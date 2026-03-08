### AtomicSync

AtomicSync is a lightweight utility that synchronizes your system clock to atomic time sources with primary and secondary NTP server failover. It syncs against NIST's primary time server and falls back to Berkeley's NTP server if the primary is unreachable, then writes the corrected time to your hardware clock for persistent accuracy.

#### Features

- Atomic-accurate time synchronization using ntpdate
- Primary/secondary NTP failover
- Hardware clock update via hwclock -w after successful sync
- Automatic logging of all sync activity to a dedicated log file
- Minimal dependencies (Bash + standard Unix tools)

#### How It Works

1. Attempts to sync system time against the primary server (time.nist.gov)
2. If the primary fails, automatically falls back to the secondary server (ntp.berkeley.edu)
3. On successful sync, writes the updated time to the hardware clock so it persists across reboots
4. All activity (successes, failures, and fallback events) is logged to atomicsync.log

#### Requirements

- `bash`
- `ntpdate`
- `hwclock`
- `sudo` privileges (required for `ntpdate` and `hwclock` -w)
- Network access to at least one of the configured NTP servers

#### Installation

Clone and make executable:

```bash
git clone https://github.com/fpucore/atomicsync.git
cd atomicsync
chmod +x AtomicSync
```

Schedule via cron for regular atomic sync (e.g. every hour):

```bash
sudo crontab -e
# Add the following line:
0 * * * * /path/to/AtomicSync
```

#### Log File

All sync activity is recorded at:

```bash
~/Blackbox-hwm/atomicsync.log
```

Each entry is timestamped and includes sync success/failure status and any fallback events.

#### Configuration

To change the NTP servers, edit the following variables in AtomicSync:

```bash
PRIMARY_SERVER="time.nist.gov"
SECONDARY_SERVER="ntp.berkeley.edu"
```

To change the log file location, edit:

```bash
LOG_FILE="$HOME/Blackbox-hwm/atomicsync.log"
```