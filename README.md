# Wwise-Unpacker
Unpack game audio Wwise files (PCK, BNK)

**This guide is for Windows-64bit only!** I'll be using the game Life is Strange **as an example**.

Here's the archive structure:

* Wwise Unpacker
  * MP3 (Unpacked MP3s)
  * OGG (Unpacked OGGs)
  * Game Files (PCK and BNK files)
  * Tools (Tools used for the unpacking process)
  * Unpack to MP3.bat
  * Unpack to OGG.bat
  
Now we have to find the audio files to unpack. Life is Strange uses Wwise audio so files are packaged in either .PCK or .BNK containers. 
You can just search for *.PCK or *.BNK but I prefer the following method: go to the game folder (C:/Program Files (x86)/Steam/steamapps/common/Life Is Strange) and search for "WwiseAudio" which will show you the audio folder for each chapter.

Inside each folder you will find the following types of files which are quite self explanatory:

* Music
* Ambiance
* Cutscene
* Sfx
* Voice files are inside "English(US)" in each folder, they start with "VO_" (Voice-over).

Keep in mind these are containers, inside each there could be either one or hundreds of audio files. Some of the largest VO containers have **over 500!** Fortunately they are all properly labeled with episode, character, location, action and mood after unpacking. 
For example: *VO_E2_2A.STM_15~Cue_E2_2A_Diner_ChloePuzzle02Happy_IGE_Chloe_200.ogg*

Find any containers you want to decode and copy them to the "Game Files" folder inside Wwise Unpacker (they can be either PCK or BNK, the unpacker handles it), then simply open "Unpack to MP3.bat" or "Unpack to OGG.bat" depending on which you like and it will do all the work for you. 
Once finished you can find all decoded files inside the "MP3" or "OGG" folder respectively.

**Things you should know about the decoder:**

* Depending on the number and size of the files it can take a while, let it run until you see the ASCII tornado.
* The decoder will offer to delete files in "Game Files" so you don't accidentally decode the same files again.
* Sometimes there can be filename conflicts while decoding (multiple files with the same name), just type "r" and hit enter on the command window when prompted. This will rename the files so you can keep all of them.
* When decoding MP3 files are first unpacked as OGG and then converted with FFmpeg and the LAME MP3 encoder. If you want the best quality possible don't use MP3, unpack it as OGG.
* The unpacker can be used for any game that uses Wwise audio, not only Life is Strange.

---

## Getting the original names back (optional)

Wwise refers to everything by 32-bit IDs, so depending on the game the decoded files may come out as
`43388703.ogg`. `Tools/wwise_names.py` renames such files using whatever name metadata is available:

* `SoundbanksInfo.xml` (or `(bankname).txt` / `Wwise_IDs.h`) — exact names, including the original
  media file names. Only usable if the game ships these files.
* `wwnames.txt` — candidate name lists; recovers *event/bank* names by computing Wwise's FNV-1 hash
  of each name. Prebuilt lists for ~250 games: https://github.com/bnnm/wwiser-utils/tree/master/wwnames

Media (`*.wem`) IDs are FNV hashes of editor GUIDs, so without `SoundbanksInfo.xml`-style metadata
only event/bank names are recoverable.

**The default `wavescan.bms` step loses IDs**, so rename *before* decoding, extracting with a script
that keeps them (`wwise_pck_extractor.bms` / `wwise_bnk_extractor.bms` from
https://github.com/bnnm/wwiser-utils/tree/master/scripts):

```
Tools\quickbms.exe wwise_pck_extractor.bms "Game Files" "Tools\Decoding"
python Tools\wwise_names.py --fetch-wwnames "Game Title"                      # or point it at the game's XML
python Tools\wwise_names.py wwnames.txt --audio-dir "Tools\Decoding"          # dry run, lists every rename
python Tools\wwise_names.py wwnames.txt --audio-dir "Tools\Decoding" --apply  # rename
```

Then decode the renamed files with `ww2ogg`/`revorb`/`ffmpeg` as usual (names carry over).
`--help` lists all options (`--csv` writes an ID→name report, `--name-style`, `--keep-media-hash`).

Two more name sources the tool understands:

* **External sources** (voice lines and similar, stored by path): name list lines that look like paths
  (`English/voice/chapter0_3_mar7th_101.wem`) are matched to the 64-bit FNV-1 hash of the path, and
  the original subfolders are recreated (`--flat` to skip). wwiser-utils ships an
  `... (External).txt` list for such games.
* **`.txtp` folders**: [wwiser](https://github.com/bnnm/wwiser) can resolve event names for streamed
  or in-bank media and write `.txtp` files that reference them; pass the `.txtp` folder as a source
  and each media ID is renamed after the event that plays it.
* **Cracking external paths**: when a game ships its original strings somewhere (config tables,
  metadata, scripts), `Tools/wwise_crack.py` harvests candidate tokens and tests them against the
  64-bit IDs, writing a name list for `wwise_names.py`:

  ```
  python Tools\wwise_crack.py --audio-dir "Tools\Decoding" --files "<game data folder>" ^
      --template "{lang}/voice/{token}.wem" --langs English Japanese --out wwnames_cracked.txt
  ```

Decoding a folder of `.wem` files with the bundled tools (skips non-Vorbis media):

```
python Tools\decode_wem.py --dir "Tools\Decoding" --out OGG --recursive
```

### Adding another game (recipe)

The tools are game-agnostic; nothing is hard-coded to a specific title. The usual order is:

1. **Extract with IDs preserved** — `wavescan.bms` carving loses the IDs, so a later rename is
   impossible. Use `wwise_pck_extractor.bms` for `.pck` (writes `<id>.wem` plus
   `externals/<16 hex>.wem`), keep `.bnk` as-is for wwiser, and dump in-bank media with
   `Tools\wwise_bnk_extract.py`.
2. **Collect name metadata, most exact first**:

   | source | recovers | how |
   |---|---|---|
   | `SoundbanksInfo.xml` / `.json`, `(bank).txt`, `Wwise_IDs.h` | exact media/event/bank names | only if the game ships them |
   | `wwnames.txt` | event/bank hashnames (32-bit) | `--fetch-wwnames "Game Title"` |
   | strings harvested from the game + `Tools\wwise_crack.py` | external paths (64-bit) and event names (32-bit, `--txtp` mode) | data tables, metadata, executables |
   | `.txtp` from [wwiser](https://github.com/bnnm/wwiser) | media ID → event name | generated from the banks |

   `wwise_crack.py` accepts extra candidate pools (`--tokens-from`, e.g. bank/object names) and
   generates common affix variants (`--variants`, `--expand N`) — that is how games whose event
   names are not shipped at all (only `play_<object>_01`-style conventions) still get named.
3. **Rename, then decode** — `wwise_names.py` (dry run, then `--apply`); check the `--csv` report;
   then `decode_wem.py`.
4. **Expect gaps**: `.wem` IDs are hashes of editor GUIDs, so media with no referenced/named event
   stay numeric. That is a property of the game data, not of the tools.

**I unpacked to .OGG for the best quality, how do I even open these files?**

You'll need a player that supports the format! Personally I use "foobar2000" but feel free to search around and find what's best for you.

---

If you end up doing something with the audio (videos for example) let me know, I really enjoy looking at other people's work. Hope this helped someone!
