# restic-status

A [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows the status of your
[resticprofile](https://creativeprojects.github.io/resticprofile/) backups in the macOS menu bar.

It reads resticprofile's **status file(s)** (JSON) and shows a single monochrome SF Symbol for
all your backups, with the details for each profile in the dropdown.

| Icon | Meaning |
| --- | --- |
| `externaldrive.badge.checkmark` | All backups succeeded and are recent |
| `externaldrive.badge.exclamationmark` | A backup is overdue (older than the max age) |
| `externaldrive.badge.xmark` | A backup, check or retention run failed, or a status file is missing or unreadable |
| `arrow.triangle.2.circlepath` | `restic backup` is running right now |
| `externaldrive.badge.questionmark` | No backups found |

When there is more than one problem, the worst one sets the icon.

The dropdown has one entry per profile: when it last ran, how long it took, how much was
added, file counts, the result of `check`/`retention` runs, the error message and the last
lines of restic's output. Each entry also has **Run backup now** and **Open status file**.

## Requirements

- [SwiftBar](https://github.com/swiftbar/SwiftBar)
- `jq`, which ships with macOS 15 and later as `/usr/bin/jq`. On older macOS, run `brew install jq`.
- resticprofile with `status-file` enabled (see below)

## 1. Enable the status file in resticprofile

Add `status-file` to each profile you want to watch. Several profiles can share one file.
Setting `extended-status = true` also records sizes and file counts.

```toml
# profiles.toml
[global]
  # ...

[default]
  status-file = "~/.config/resticprofile/status.json"

  [default.backup]
    extended-status = true
```

```yaml
# profiles.yaml
default:
  status-file: ~/.config/resticprofile/status.json
  backup:
    extended-status: true
```

The file is written after the next backup run.

## 2. Install the plugin

```sh
git clone https://github.com/bastipnt/restic-status.git
ln -s "$PWD/restic-status/restic-status.5m.sh" "$(defaults read com.ameba.SwiftBar PluginDirectory)/"
```

Or copy `restic-status.5m.sh` into your SwiftBar plugin folder and run
`chmod +x restic-status.5m.sh`. The `5m` in the file name sets the refresh interval. Rename
the file to change it, for example to `restic-status.1m.sh`.

## 3. Configure

You can set the options in either of two places:

- **SwiftBar UI**: right-click the plugin, open **Plugin settings**, and edit the environment
  variables.
- **Config file**: `~/.config/restic-status/config` holds shell `KEY=value` lines. Use
  **Edit configuration…** in the menu to create and open it. When this file exists, its
  values override the environment variables.

| Variable | Default | Description |
| --- | --- | --- |
| `RESTIC_STATUS_FILES` | `~/.config/resticprofile/status.json` | Status files to read, separated by commas (or colons) |
| `RESTIC_MAX_AGE_HOURS` | `26` | Mark a backup as overdue after this many hours (`0` turns this off) |
| `RESTIC_MAX_AGE_HOURS_<profile>` | – | Max age for one profile (characters other than letters, digits and `_` in the name become `_`) |
| `RESTIC_SHOW_COUNT` | `0` | `1` shows the number of problems next to the icon |
| `RESTIC_DETECT_RUNNING` | `1` | Show the "running" icon while `restic backup` runs |
| `RESTICPROFILE_BIN` | found in `PATH` | resticprofile binary used by "Run backup now" |
| `RESTICPROFILE_CONFIG` | – | `--config` passed to resticprofile by "Run backup now" |
| `RESTIC_STATUS_CONFIG` | `~/.config/restic-status/config` | Location of the config file |

Example:

```sh
# ~/.config/restic-status/config
RESTIC_STATUS_FILES="~/.config/resticprofile/status.json, ~/Library/Application Support/resticprofile/nas-status.json"
RESTIC_MAX_AGE_HOURS=26
RESTIC_MAX_AGE_HOURS_photos=170   # weekly backup
RESTICPROFILE_CONFIG=~/.config/resticprofile/profiles.toml
```

"Run backup now" runs `resticprofile --name <profile> backup` in the background. Its output
goes to `~/Library/Logs/restic-status/<profile>.log`.

## Development

```sh
tests/run.sh          # runs the plugin against tests/fixtures/*.json
shellcheck restic-status.5m.sh
```

The script targets the bash 3.2 that ships with macOS and needs only `jq`.
