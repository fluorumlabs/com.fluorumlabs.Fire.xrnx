# AKAI Fire Integration for Renoise 3.1

![To be replaced with an actual photo ;)](https://d1jtxvnvoxswj8.cloudfront.net/catalog/product/cache/ecd051e9670bd57df35c8f0b122d8aea/a/k/akai-fire-top-view.jpg)

This tool allows to use AKAI Fire FL Studio controller with Renoise tracker. It packs quite a lot of no-nonsense Renoise features to be available at your fingertips. Note: I made it for myself, so it may or may not suit your tracking style ;)

# Limitations

- Navigation in multiples of 16 steps
- No support for OLED display
- No support for multiple AKAI Fire controllers
- Something else I forgot :)

# Features

- Mode LEDs show beat position within pattern in binary format: `CHANNEL` toggles every 1/16 of pattern, `MIXER` toggles every 1/8, `USER 1` - every 1/4 and `USER 2` - every 1/2.
- Pad color in Note mode (or in Drum mode with `STEP` held) represents note (12 semitones of octave mapped to a hue); active notes (not stopped by note-offs) are showed in a dim color
- Pad color in Drum mode represents track color
- Pad color in Performance mode represents track color
- Pad color in Overview mode: 1st row: current pattern, 3rd row: solo state, 4th row: mute state
- Tapping pad in Drum mode captures the nearest note/instrument before of after tapped position
- Both live loop recording and stepped recording are supported (set step size with `STEP`+`⟲/⟳ SELECT` and use `STEP`/`SHIFT`+`STEP` to skip steps)

# Reference

## Global Shortcuts

### Transport

Combination | Function
----------- | --------
`PATTERN/SONG` | Switch "Repeat pattern" on/off
`PLAY` | (Re)start playback of current pattern
_`WAIT`_ a.k.a. `SHIFT`+`PLAY` | Continue playback
`STOP` | Stop playback
`REC` | Swith "Edit mode" on/off

### Mode selection

Combination | Function
----------- | --------
`NOTE` | Switch to note step editor (see [Note/Drum Mode Shortcuts]())
`DRUM` | Switch to pattern (see [Note/Drum Mode Shortcuts]())
`PERFORM` | Cycle between pattern matrix mode (see [Performance Mode Shortcuts]()) and mixer mide (see [Overview Mode Shortcuts]())
`BROWSE` | Activate instrument selection panel (see [Browser Shortcuts]())

### Miscellaneus

Combination | Function
----------- | --------
_`SNAP`_ a.k.a. `SHIFT`+`NOTE` | Switch live record quantize on/off
_`TAP`_ a.k.a. `SHIFT`+`DRUM` | Switch pattern editor block loop on/off
_`OVERVIEW`_ a.k.a. `SHIFT`+`PERFORM` | Show/hide spectrum analyzer
_`METRONOME`_ a.k.a. `SHIFT`+`PATTERN/SONG` | Switch "Metronome" on/off
_`COUNTDOWN`_ a.k.a. `SHIFT`+`STOP` | Switch "Metronome pre-count" on/off
_`LOOP REC`_ a.k.a. `SHIFT`+`REC` | Switch "Follow player" on/off
`MODE`+`⟲ SELECT` | Undo
`MODE`+`⟳ SELECT` | Redo

## Browser Shortcuts

Combination | Function
----------- | --------
`⟲ SELECT` | Select previous instrument
`⟳ SELECT` | Select next instrument

## Note/Drum Mode Shortcuts

### Navigation

Combination | Function
----------- | --------
`▲ PATTERN` | Scroll up
`▼ PATTERN` | Scroll down
`▶ GRID` | Scroll right (show next page of 16 steps)
`◀ GRID` | Scroll left (show previous page of 16 steps)
`SHIFT`+`▲ PATTERN` | Select previous track
`SHIFT`+`▼ PATTERN` | Select next track
`ALT`+`▲ PATTERN` | Insert new track before current
`ALT`+`▼ PATTERN` | Insert new track after current
`SHIFT`+`ALT`+`▲ PATTERN` | Delete current track and select previous
`SHIFT`+`ALT`+`▼ PATTERN` | Delete current track and select next
`SHIFT`+`*MUTE*` | Add new note column
`ALT`+`*MUTE*` | Duplicate note column
`SHIFT`+`ALT`+`*MUTE*` | Clear note column or delete if it's empty throughout the whole song
`STEP` | Move cursor to next step in pattern editor
`SHIFT`+`STEP` | Move cursor to previous step in pattern editor
`STEP`+`⟲/⟳ SELECT` | Change step size

### Selection

Combination | Function
----------- | --------
`*PAD*` | Select note column line in pattern (also set/clear step in Drum Mode)
`*PAD*`+`*PAD*` | Select block in pattern
`SHIFT`+`*PAD*` | Select block in pattern, starting at previously selected note column line
`*MUTE*` | Select whole note column or whole track

### Editing

Combination | Function
----------- | --------
`STEP`+`*PAD*` | Set/clear note off
`⟲/⟳ VOLUME` | Adjust selection volume
`⟲/⟳ PANNING` | Adjust selection panning
`⟲/⟳ FILTER` | Adjust selection delay
`⟲/⟳ RESONANCE` | Adjust hue color of current track
`⟲/⟳ SELECT` | Transpose selection
`ALT`+`⟲/⟳ SELECT` | Increment/decrement instrument within selection
`ALT`+`SHIFT`+`VOLUME/PANNING/FILTER (touch)` | Clear volume/panning/delay of selection
`MODE`+`VOLUME/PANNING (touch)` | Interpolate volume/panning within selection

### Block operations

Combination | Function
----------- | --------
`ALT`+`*PAD*` | Paste selection at desired position
`SHIFT`+`ALT`+`*PAD*` | Clear selection
`SHIFT`+`⟲/⟳ SELECT` | Move selected block forward/backward, or rotate, if whole pattern is selected
`SHIFT`+`▶ GRID` | Shift page content (16 steps) to next page
`SHIFT`+`◀ GRID` | Shift page content (16 steps) to previous page
`ALT`+`▶ GRID` | Duplicate page content (16 steps) to next page
`ALT`+`◀ GRID` | Duplicate page content (16 steps) to previous page
`SHIFT`+`ALT`+`▶ GRID` | Clear current page (16 steps) and select next
`SHIFT`+`ALT`+`◀ GRID` | Clear current page (16 steps) and select previous

### Miscellaneous

Combination | Function
----------- | --------
`STEP`+`*MUTE*` | Switch slot mute for current track

## Performance Mode Shortcuts

### Navigation

Combination | Function
----------- | --------
`▲ PATTERN` | Scroll up
`▼ PATTERN` | Scroll down
`⟲/⟳ SELECT` | Scroll up/down
`▶ GRID` | Scroll right
`◀ GRID` | Scroll left

### Editing

Combination | Function
----------- | --------
`*PAD*` | Select slot
`*PAD*`+`*PAD*` | Duplicate slot
`ALT`+`*PAD*` | Duplicate selected slot
`SHIFT`+`*PAD*` | Move selected slot
`SHIFT`+`ALT`+`*PAD*` | Clear slot
`⟲/⟳ VOLUME` | Adjust mixer volume for selected track
`⟲/⟳ PANNING` | Adjust mixer panning for selected track
`⟲/⟳ RESONANCE` | Adjust hue color for selected track
`SHIFT`+`*MUTE*` | Add new pattern to sequence
`ALT`+`*MUTE*` | Duplicate pattern in sequence
`SHIFT`+`ALT`+`*MUTE*` | Delete pattern from sequence

### Sequencing

Combination | Function
----------- | --------
`*MUTE*` | Schedule pattern/start playback if stopped
`STEP`+`*MUTE*` | Switch to pattern immediately
`STEP`+`*PAD*` | Mute/unmute slot

## Overview Mode Shortcuts
Combination | Function
----------- | --------
`*PAD*` (1st row) | Select slot
`*PAD*` (3rd row) | Toggle track solo
`*PAD*` (4th row) | Toggle track mute
`⟲/⟳ VOLUME` | Adjust mixer volume for selected track
`⟲/⟳ PANNING` | Adjust mixer panning for selected track
`⟲/⟳ RESONANCE` | Adjust hue color for selected track
