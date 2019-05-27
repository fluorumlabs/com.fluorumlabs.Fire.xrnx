# AKAI Fire Integration for Renoise 3.1

![To be replaced with an actual photo ;)](https://d1jtxvnvoxswj8.cloudfront.net/catalog/product/cache/ecd051e9670bd57df35c8f0b122d8aea/a/k/akai-fire-top-view.jpg)

This tool allows to use AKAI Fire FL Studio controller with Renoise tracker. It packs quite a lot of no-nonsense Renoise features to be available at your fingertips. Note: I made it for myself, so it may or may not suit your tracking style ;)

# Reference

## Global Shortcuts

### Transport

Combination | Function
----------- | --------
`PATTERN/SONG` | Switch "Repeat pattern" on/off
`PLAY` | (Re)start playback of current pattern
_`WAIT`_ a.k.a. `SHIFT` + `PLAY` | Continue playback
`STOP` | Stop playback
`REC` | Swith "Edit mode" on/off

### Mode selection

Combination | Function
----------- | --------
`NOTE` | Switch to note step editor (see [Note/Drum Mode Shortcuts]())
`DRUM` | Switch to pattern (see [Note/Drum Mode Shortcuts]())
`PERFORM` | Switch to pattern matrix mode (see [Performance Mode Shortcuts]())

### Miscellaneus

Combination | Function
----------- | --------
_`SNAP`_ a.k.a. `SHIFT` + `NOTE` | Switch live record quantize on/off
_`TAP`_ a.k.a. `SHIFT` + `DRUM` | Switch pattern editor block loop on/off
_`OVERVIEW`_ a.k.a. `SHIFT` + `PERFORM` | Show/hide spectrum analyzer
`BROWSER` | Show/hide instrument selection panel (see [Browser Shortcuts]())
`MODE` + `⟲ SELECT` | Undo
`MODE` + `⟳ SELECT` | Redo

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
`▶ GRID` | Scroll right (show next 16 steps)
`◀ GRID` | Scroll left (show previous 16 steps)
`SHIFT` + `▲ PATTERN` | Select previous track
`SHIFT` + `▼ PATTERN` | Select next track
`STEP` | Move cursor to next step in pattern editor
`SHIFT` + `STEP` | Move cursor to previous step in pattern editor
`STEP` + `⟲/⟳ SELECT` | Change step size

### Selection

Combination | Function
----------- | --------
`*PAD*` | Select note column line in pattern (also set/clear step in Drum Mode)
`*PAD*` + `*PAD*` | Select block in pattern
`SHIFT` + `*PAD*` | Select block in pattern, starting at previously selected note column line
`*MUTE*` | Select whole note column
`2× *MUTE*` | Select whole track

### Editing

Combination | Function
----------- | --------
`STEP` + `*PAD*` | Set/clear note off
`⟲/⟳ VOLUME` | Adjust selection volume
`⟲/⟳ PANNING` | Adjust selection panning
`⟲/⟳ FILTER` | Adjust selection delay
`⟲/⟳ RESONANCE` | Adjust hue color of current track
`⟲/⟳ SELECT` | Transpose selection
`ALT` + `⟲/⟳ SELECT` | Increment/decrement instrument within selection
`ALT` + `SHIFT` + `VOLUME/PANNING/FILTER (touch)` | Clear volume/panning/delay of selection
`MODE` + `VOLUME/PANNING (touch)` | Interpolate volume/panning within selection

### Block operations

Combination | Function
----------- | --------
`ALT` + `*PAD*` | Paste selection at desired position
`SHIFT` + `⟲/⟳ SELECT` | Move selected block forward/backward, or rotate, if whole pattern is selected
`SHIFT` + 
`STEP` + `*MUTE*` | Switch slot mute for current track
`⟲ VOLUME` | Decrease volu
`⟳ SELECT` | Select next instrument