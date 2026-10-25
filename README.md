# MicDrop 🎤

A karaoke player for iPhone and iPad that plays **your own** files.

- **MP3+CDG**: separate files with matching names, or zipped together
- **Video karaoke**: MP4 / M4V / MOV
- **Plain audio**: MP3, M4A, AAC, WAV, FLAC, AIFF
- **Key change** (±12 semitones) and **tempo** (50–150%) for MP3+CDG and audio. Video files get tempo only for now.
- **Singer queue** with names, drag to reorder, auto-advance
- **TV output** over AirPlay Screen Mirroring or HDMI: the TV shows only the lyrics/video, the phone stays the remote, and the TV shows who's up next between songs
- **Library**: scans the app's folder in Files plus any linked folders (iCloud Drive, USB drives…) with no copying needed. Search by artist, title or file name.
- Plays in the background, with lock screen controls and an adjustable lyrics offset for Bluetooth delay

## Adding songs

Any of these:

1. **Files app** → On My iPhone → **MicDrop** → copy or move files in (subfolders are fine).
2. In the app: **Songs → + → Import Files…**
3. **Songs → + → Link Folder…** to scan a folder in place, e.g. an iCloud Drive folder.
4. **AirDrop / Share → MicDrop** from another app.
5. **Songs → + → Get from OpenKJ…** to search an [OpenKJ](https://github.com/gtachibana/OpenKJ) library on
   your network and download songs (MP3+CDG pairs arrive as one zip). In OpenKJ, turn on Local Mode and its
   embedded server and set an admin password, then connect with the PC's IP address and that password.
   Downloads go in the `OpenKJ` subfolder.

Name files `Artist - Title.mp3` + `Artist - Title.cdg` (or `.zip`). A disc ID prefix such as
`SC8123-05 - Artist - Title` is ignored. If your files are named `Title - Artist`, change that in Settings.

## Building

There's no Mac needed. Every push to `main` builds an unsigned `MicDrop.ipa` on GitHub Actions
(see `.github/workflows/build.yml`). The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

Download the latest build:

```sh
gh run download --repo gtachibana/micdrop --name MicDrop-ipa --dir dist
```

## Installing (sideloading) from Windows

1. Install **[Sideloadly](https://sideloadly.io)**. It needs iTunes and iCloud for Windows, the
   versions from Apple's website rather than the Microsoft Store.
2. Connect your iPhone by USB and tap **Trust** on the phone.
3. Drag `MicDrop.ipa` into Sideloadly, enter your Apple ID, and click **Start**.
4. On the iPhone, go to **Settings → General → VPN & Device Management** and trust your Apple ID.
5. Turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode. The phone restarts.

With a free Apple ID the app expires after **7 days**. Re-run Sideloadly to refresh it; your songs
and queue are kept. A paid developer account extends that to a year.
