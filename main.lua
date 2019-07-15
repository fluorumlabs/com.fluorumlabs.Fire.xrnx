-- set up include-path
_clibroot = 'cLib/classes/'
_xlibroot = 'xLib/classes/'

_trace_filters = nil

-- require some classes
require(_clibroot .. 'cDebug')
require(_xlibroot .. 'xLib')
require(_xlibroot .. 'xPatternSequencer')

rns = nil

local MY_INTERFACE
local MY_INTERFACE_RACK

local MIDI_IN
local MIDI_OUT

local OPTIONS = renoise.Document.create("ScriptingToolPreferences") {
    MidiInput = "FL STUDIO FIRE",
    MidiOutput = "FL STUDIO FIRE",
    DevelopmentMode = false,
}

renoise.tool().preferences = OPTIONS

local MIDI_IN_PORT = OPTIONS.MidiInput.value
local MIDI_OUT_PORT = OPTIONS.MidiOutput.value

local PAD_ROWS = 4
local PAD_COLUMNS = 16
local PADS = table.create()
local PADS_2ND = table.create()
local ROW_SELECT = table.create()
local ROW_SELECT_2ND = table.create()
local ROW_INDICATOR = table.create()
local ROW_INDICATOR_2ND = table.create()

local PADS_DEBUG = table.create()
local ROW_SELECT_DEBUG = table.create()
local ROW_INDICATOR_DEBUG = table.create()

local MODE_NOTE = 1
local MODE_DRUM = 2
local MODE_PERFORM = 3
local MODE_OVERVIEW = 4

local MODE = MODE_PERFORM

local NOTE_STEP_VIEW_POS = 1
local NOTE_COLUMN_VIEW_POS = 1
local NOTE_CURSOR_POS = 1

local PERFORM_TRACK_VIEW_POS = 1
local PERFORM_SEQUENCE_VIEW_POS = 1

local CURRENT_PATTERN
local CURRENT_LINE = -1
local CURRENT_SEQUENCE = -1
local CURRENT_TRACK = -1
local CURRENT_NOTE_COLUMN = -1
local PLAYBACK_LINE = -1
local PLAYBACK_SEQUENCE = -1
local PLAYBACK_NEXT_SEQUENCE = -1

local PLAYBACK_BEAT_IN_PATTERN = 1

local UI_MODE = 1
local UI_MODE_PRESSED = false
local UI_MODE_DEBUG

local UI_KNOB1_DEBUG
local UI_KNOB2_DEBUG
local UI_KNOB3_DEBUG
local UI_KNOB4_DEBUG

local UI_PAD_PRESSED_COUNT = 0
local UI_PAD_PROCESSED = false

local UI_BROWSE_PRESSED = false
local UI_BROWSE_DEBUG

local UI_PATTERN_PREV_DEBUG
local UI_PATTERN_NEXT_DEBUG
local UI_GRID_PREV_DEBUG
local UI_GRID_NEXT_DEBUG

local UI_STEP_PRESSED = false
local UI_STEP_PROCESSED = false
local UI_STEP_DEBUG
local UI_NOTE_DEBUG
local UI_DRUM_DEBUG
local UI_PERFORM_DEBUG
local UI_SHIFT_PRESSED = false
local UI_SHIFT_DEBUG
local UI_ALT_PRESSED = false
local UI_ALT_DEBUG
local UI_SONG_DEBUG
local UI_PLAY_DEBUG
local UI_STOP_DEBUG
local UI_REC_DEBUG

local QUEUE_RENDER = false

local COLOR_OFF = { 0, 0, 0 }
local COLOR_RED_LOW = { 127, 0, 0 }
local COLOR_RED = { 255, 0, 0 }
local COLOR_GREEN = { 0, 255, 0 }
local COLOR_YELLOW = { 255, 255, 0 }

local INITIALIZED = false

function initialize()
    renoise.tool().app_new_document_observable:add_notifier(function()
        rns = renoise.song()
        CURRENT_PATTERN = nil
        rns_initialize()
    end)
    rns = nil
end

function rns_initialize()
    for r = 1, PAD_ROWS do
        PADS[r] = table.create()
        PADS_2ND[r] = table.create()
        ROW_SELECT[r] = { 0, 0, 0 }
        ROW_SELECT_2ND[r] = { -1, -1, -1 }
        ROW_INDICATOR[r] = { 0, 0, 0 }
        ROW_INDICATOR_2ND[r] = { -1, -1, -1 }
        for c = 1, PAD_COLUMNS do
            PADS[r][c] = { 0, 0, 0, false }
            PADS_2ND[r][c] = { -1, -1, -1, false }
        end
    end

    if not INITIALIZED then
        INITIALIZED = true

        build_debug_interface()
        midi_init()
        ui_update_state_buttons()
        ui_update_nav_buttons()
        mark_as_dirty()
    end

    attach_notifier(nil)

    if not (rns.selected_pattern_observable:has_notifier(attach_notifier)) then
        rns.selected_pattern_observable:add_notifier(attach_notifier)
    end
    if not (renoise.tool().app_idle_observable:has_notifier(idler)) then
        renoise.tool().app_idle_observable:add_notifier(idler)
    end
    if not (rns.tracks_observable:has_notifier(mark_as_dirty)) then
        rns.tracks_observable:add_notifier(mark_as_dirty)
    end
    if not (rns.sequencer.pattern_sequence_observable:has_notifier(mark_as_dirty)) then
        rns.sequencer.pattern_sequence_observable:add_notifier(mark_as_dirty)
    end
    if not (renoise.tool().app_release_document_observable:has_notifier(mark_as_dirty)) then
        renoise.tool().app_release_document_observable:add_notifier(mark_as_dirty)
    end
    if not (rns.transport.playing_observable:has_notifier(ui_update_transport_buttons)) then
        rns.transport.playing_observable:add_notifier(ui_update_transport_buttons)
    end
    if not (rns.transport.loop_pattern_observable:has_notifier(ui_update_transport_buttons)) then
        rns.transport.loop_pattern_observable:add_notifier(ui_update_transport_buttons)
    end
    if not (rns.transport.edit_mode_observable:has_notifier(ui_update_transport_buttons)) then
        rns.transport.edit_mode_observable:add_notifier(ui_update_transport_buttons)
    end

    idler()
end

function attach_notifier(_)
    if CURRENT_PATTERN ~= nil then
        CURRENT_PATTERN:remove_line_notifier(mark_as_dirty)
    end
    CURRENT_PATTERN = rns.selected_pattern
    if not (CURRENT_PATTERN:has_line_notifier(mark_as_dirty)) then
        CURRENT_PATTERN:add_line_notifier(mark_as_dirty)
    end
    mark_as_dirty()
    ui_update_nav_buttons()
end

function mark_as_dirty()
    QUEUE_RENDER = true
end

function idler(_)
    local new_line_index = rns.selected_line_index
    local new_sequence_index = rns.selected_sequence_index
    local new_track_index = rns.selected_track_index
    local new_note_column_index = rns.selected_note_column_index
    local new_playback_line = rns.transport.playback_pos.line
    local new_playback_sequence = rns.transport.playback_pos.sequence
    local lpb = rns.transport.lpb

    if CURRENT_LINE ~= new_line_index then
        CURRENT_LINE = new_line_index
        focus_line()
        QUEUE_RENDER = true
    end
    if CURRENT_NOTE_COLUMN ~= new_note_column_index and new_note_column_index > 0 then
        CURRENT_NOTE_COLUMN = new_note_column_index
        focus_note_column()
        QUEUE_RENDER = true
    end
    if CURRENT_TRACK ~= new_track_index and new_note_column_index > 0 then
        CURRENT_TRACK = new_track_index
        focus_track()
        focus_note_column()
        QUEUE_RENDER = true
    end
    if CURRENT_SEQUENCE ~= new_sequence_index then
        CURRENT_SEQUENCE = new_sequence_index
        focus_sequence()
        QUEUE_RENDER = true
    end

    if UI_MODE ~= PLAYBACK_BEAT_IN_PATTERN then
        UI_MODE = PLAYBACK_BEAT_IN_PATTERN
        midi_mode(math.floor(16 * lpb * PLAYBACK_BEAT_IN_PATTERN / rns:pattern(rns.sequencer:pattern(PLAYBACK_SEQUENCE)).number_of_lines))
    end

    if QUEUE_RENDER then
        QUEUE_RENDER = false
        render()
        render_debug()
    elseif PLAYBACK_LINE ~= new_playback_line or PLAYBACK_SEQUENCE ~= new_playback_sequence then
        PLAYBACK_LINE = new_playback_line
        PLAYBACK_SEQUENCE = new_playback_sequence
        PLAYBACK_BEAT_IN_PATTERN = math.floor(PLAYBACK_LINE / lpb)
        if PLAYBACK_NEXT_SEQUENCE == PLAYBACK_SEQUENCE then
            PLAYBACK_NEXT_SEQUENCE = -1
        end
        if MODE == MODE_DRUM or MODE == MODE_NOTE then
            render_note_cursor(rns)
        elseif MODE == MODE_PERFORM or MODE == MODE_OVERVIEW then
            render()
        end
        render_debug()
    end

end

function render()
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        render_note()
    elseif MODE == MODE_PERFORM then
        render_perform()
    elseif MODE == MODE_OVERVIEW then
        render_overview()
    end
end

function render_debug()
    -- render to debug surface
    for r = 1, PAD_ROWS do
        if ROW_SELECT[r][1] ~= ROW_SELECT_2ND[r][1] or ROW_SELECT[r][2] ~= ROW_SELECT_2ND[r][2] or ROW_SELECT[r][3] ~= ROW_SELECT_2ND[r][3] then
            ROW_SELECT_2ND[r] = table.copy(ROW_SELECT[r])
            midi_row(r, ROW_SELECT_2ND[r])
            ROW_SELECT_DEBUG[r].color = ROW_SELECT_2ND[r]
        end

        if ROW_INDICATOR[r][1] ~= ROW_INDICATOR_2ND[r][1] or ROW_INDICATOR[r][2] ~= ROW_INDICATOR_2ND[r][2] or ROW_INDICATOR[r][3] ~= ROW_INDICATOR_2ND[r][3] then
            ROW_INDICATOR_2ND[r] = table.copy(ROW_INDICATOR[r])
            midi_indicator(r, ROW_INDICATOR_2ND[r])
            ROW_INDICATOR_DEBUG[r].color = ROW_INDICATOR_2ND[r]
        end

        local sysex = midi_pad_start()

        for c = 1, PAD_COLUMNS do
            if PADS[r][c][1] ~= PADS_2ND[r][c][1] or PADS[r][c][2] ~= PADS_2ND[r][c][2] or PADS[r][c][3] ~= PADS_2ND[r][c][3] or PADS[r][c][4] ~= PADS_2ND[r][c][4] then
                PADS_2ND[r][c] = table.copy(PADS[r][c])
                local hsv = table.copy(PADS[r][c])
                if hsv[2] == 0 and hsv[3] == 0 then
                    hsv[1] = 0
                    hsv[3] = 0
                    if hsv[4] then
                        hsv[2] = 0.5
                    end
                else
                    if hsv[4] then
                        hsv[2] = hsv[2] - 0.2
                        hsv[2] = math.max(hsv[2], 0)
                    end
                end
                hsv[1] = math.floor(hsv[1] * 12) / 12;

                midi_pad(sysex, r, c, hsv_to_rgb(hsv))
            end
        end

        midi_pad_end(sysex)
    end
end

function focus_track()
    if CURRENT_TRACK > PERFORM_TRACK_VIEW_POS + PAD_COLUMNS then
        PERFORM_TRACK_VIEW_POS = CURRENT_TRACK - PAD_COLUMNS + 1
        ui_update_nav_buttons()
    elseif CURRENT_TRACK < PERFORM_TRACK_VIEW_POS then
        PERFORM_TRACK_VIEW_POS = CURRENT_TRACK
        ui_update_nav_buttons()
    end
end

function focus_sequence()
    if CURRENT_SEQUENCE > PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS then
        PERFORM_SEQUENCE_VIEW_POS = CURRENT_SEQUENCE - PAD_ROWS + 1
        ui_update_nav_buttons()
    elseif CURRENT_SEQUENCE < PERFORM_SEQUENCE_VIEW_POS then
        PERFORM_SEQUENCE_VIEW_POS = CURRENT_SEQUENCE
        ui_update_nav_buttons()
    end
end

function focus_note_column()
    if CURRENT_NOTE_COLUMN > NOTE_COLUMN_VIEW_POS + PAD_ROWS then
        NOTE_COLUMN_VIEW_POS = CURRENT_NOTE_COLUMN - PAD_ROWS + 1
        ui_update_nav_buttons()
    elseif CURRENT_NOTE_COLUMN < NOTE_COLUMN_VIEW_POS then
        NOTE_COLUMN_VIEW_POS = CURRENT_NOTE_COLUMN
        ui_update_nav_buttons()
    end
end

function focus_line()
    local new_note_step_view_pos = CURRENT_LINE - ((CURRENT_LINE - 1) % PAD_COLUMNS)
    if new_note_step_view_pos ~= NOTE_STEP_VIEW_POS then
        NOTE_STEP_VIEW_POS = new_note_step_view_pos
        ui_update_nav_buttons()
    end
end

function render_perform()
    for i = PERFORM_SEQUENCE_VIEW_POS, PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS - 1 do
        if i == PLAYBACK_SEQUENCE then
            ROW_SELECT[i - PERFORM_SEQUENCE_VIEW_POS + 1] = { 0, 255, 0 }
        else
            ROW_SELECT[i - PERFORM_SEQUENCE_VIEW_POS + 1] = { 0, 0, 0 }
        end
        if i == PLAYBACK_NEXT_SEQUENCE then
            ROW_INDICATOR[i - PERFORM_SEQUENCE_VIEW_POS + 1] = { 0, 255, 0 }
        else
            ROW_INDICATOR[i - PERFORM_SEQUENCE_VIEW_POS + 1] = { 0, 0, 0 }
        end
        for j = PERFORM_TRACK_VIEW_POS, PERFORM_TRACK_VIEW_POS + PAD_COLUMNS - 1 do
            if i >= 1 and i <= #rns.sequencer.pattern_sequence and j >= 1 and j <= rns.sequencer_track_count then
                local cell = rns:pattern(rns.sequencer:pattern(i)):track(j)
                --local is_alias = false
                --if cell.is_alias then
                --    is_alias = true
                --    cell = rns:pattern(cell.alias_pattern_index):track(j)
                --end
                if cell.color ~= nil then
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1] = rgb_to_hsv(cell.color)
                else
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1] = rgb_to_hsv(rns:track(j).color)
                end
                PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 1.0
                if cell.is_empty then
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][1] = 0
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0
                elseif i == PLAYBACK_SEQUENCE then
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0.5
                    PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 1.0
                    --if not is_alias then
                    --    PADS[i][j][3] = PADS[i][j][3] * 2
                    --end
                else
                    if i == PLAYBACK_SEQUENCE then
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0.5
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 1.0
                        --if not is_alias then
                        --    PADS[i][j][3] = PADS[i][j][3] * 2
                        --end
                    else
                        if PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][1] ~= 0 or PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] ~= 0 then
                            if rns.sequencer:track_sequence_slot_is_muted(j - PERFORM_TRACK_VIEW_POS + 1, i - PERFORM_SEQUENCE_VIEW_POS + 1) then
                                PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0.2
                            else
                                PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0.2
                            end

                        end
                    end
                end
                if i == CURRENT_SEQUENCE and j == CURRENT_TRACK then
                    if PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][1] ~= 0 or PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] ~= 0 then
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 1.0
                    else
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0
                        PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0.5
                    end
                end
            else
                PADS[i - PERFORM_SEQUENCE_VIEW_POS + 1][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
            end
        end
    end
end

function render_overview()
    ROW_SELECT[1] = { 0, 255, 0 }
    if PLAYBACK_NEXT_SEQUENCE == -1 or PLAYBACK_NEXT_SEQUENCE == PLAYBACK_SEQUENCE then
        ROW_INDICATOR[1] = { 0, 255, 0 }
    else
        ROW_INDICATOR[1] = { 0, 0, 0 }
    end
    ROW_SELECT[2] = { 0, 0, 0 }
    ROW_SELECT[3] = { 0, 0, 0 }
    ROW_SELECT[4] = { 0, 0, 0 }
    ROW_INDICATOR[2] = { 0, 0, 0 }
    ROW_INDICATOR[3] = { 0, 0, 0 }
    ROW_INDICATOR[4] = { 0, 0, 0 }

    for j = PERFORM_TRACK_VIEW_POS, PERFORM_TRACK_VIEW_POS + PAD_COLUMNS - 1 do
        if j >= 1 and j <= rns.sequencer_track_count then
            local cell = rns:pattern(rns.sequencer:pattern(PLAYBACK_SEQUENCE)):track(j)
            if cell.color ~= nil then
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1] = rgb_to_hsv(cell.color)
            else
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1] = rgb_to_hsv(rns:track(j).color)
            end
            PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 1.0
            if cell.is_empty then
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][1] = 0
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0
            else
                PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 1.0
            end
            if j == CURRENT_TRACK then
                if PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][1] ~= 0 or PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][2] ~= 0 then
                    PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0.2
                else
                    PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][2] = 0
                    PADS[1][j - PERFORM_TRACK_VIEW_POS + 1][3] = 0.5
                end
            end

            PADS[2][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
            if rns:track(j).solo_state then
                PADS[3][j - PERFORM_TRACK_VIEW_POS + 1] = { 0.4, 1.0, 1.0, false }
                if rns:track(j).mute_state ~= renoise.Track.MUTE_STATE_ACTIVE then
                    PADS[4][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 1.0, 0.2, false }
                else
                    PADS[4][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
                end
            else
                PADS[3][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
                if rns:track(j).mute_state ~= renoise.Track.MUTE_STATE_ACTIVE then
                    PADS[4][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 1.0, 1.0, false }
                else
                    PADS[4][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
                end
            end
        else
            PADS[1][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
            PADS[2][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
            PADS[3][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
            PADS[4][j - PERFORM_TRACK_VIEW_POS + 1] = { 0, 0, 0, false }
        end
    end
end

function render_note_cursor()
    local new_step_pos = PLAYBACK_LINE - NOTE_STEP_VIEW_POS + 1
    if rns.selected_sequence_index ~= PLAYBACK_SEQUENCE or new_step_pos <= 0 or new_step_pos > PAD_COLUMNS then
        new_step_pos = 0
    end

    for i = 1, PAD_ROWS do
        if NOTE_COLUMN_VIEW_POS + i - 1 == CURRENT_NOTE_COLUMN then
            ROW_SELECT[i] = { 0, 255, 0 }
        else
            ROW_SELECT[i] = { 0, 0, 0 }
        end

        if NOTE_COLUMN_VIEW_POS + i - 1 <= rns:track(rns.selected_track_index).visible_note_columns then
            ROW_INDICATOR[i] = { 0, 127, 0 }
        else
            ROW_INDICATOR[i] = { 0, 0, 0 }
        end

        if NOTE_CURSOR_POS > 0 then
            PADS[i][NOTE_CURSOR_POS][4] = false
        end
        if new_step_pos > 0 and NOTE_COLUMN_VIEW_POS + i - 1 <= rns:track(rns.selected_track_index).visible_note_columns then
            PADS[i][new_step_pos][4] = true
        end
    end

    NOTE_CURSOR_POS = new_step_pos
end

function render_note()
    render_note_cursor()
    local column_num = rns:track(rns.selected_track_index).visible_note_columns
    local last_note = table.create()
    local last_volume = table.create()

    if MODE == MODE_NOTE or (MODE == MODE_DRUM and UI_STEP_PRESSED) then
        for i = 1, column_num do
            last_note[i] = -1
        end
        for pos, line in rns.pattern_iterator:note_columns_in_pattern_track(rns.selected_pattern_index, rns.selected_track_index, true) do
            if pos.line >= NOTE_STEP_VIEW_POS then
                break
            end
            local note_value = line.note_value
            if note_value == 120 then
                last_note[pos.column] = -1
                last_volume[pos.column] = 0
            elseif note_value < 120 then
                last_note[pos.column] = note_value % 12
                last_volume[pos.column] = line.volume_value
            end
        end
        for i = NOTE_COLUMN_VIEW_POS, NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 do
            if i <= column_num then
                render_note_row(i, last_note[i], last_volume[i])
            else
                for j = 1, PAD_COLUMNS do
                    PADS[i - NOTE_COLUMN_VIEW_POS + 1][j] = { 0, 0, 0, false }
                end
            end
        end
    else
        for i = NOTE_COLUMN_VIEW_POS, NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 do
            if i <= column_num then
                render_drum_row(i, last_note[i])
            else
                for j = 1, PAD_COLUMNS do
                    PADS[i - NOTE_COLUMN_VIEW_POS + 1][j] = { 0, 0, 0, false }
                end
            end
        end
    end
end

function is_selected_column(track, column, selection)
    if selection == nil then
        return track == rns.selected_track_index and column == CURRENT_NOTE_COLUMN
    end
    if track < selection.start_track or track > selection.end_track then
        return false
    end
    if track == selection.start_track and column < selection.start_column then
        return false
    end
    if track == selection.end_track and column > selection.end_column then
        return false
    end
    return true
end

function is_selected_line(line, selection)
    if selection == nil then
        return line == CURRENT_LINE
    end
    if line < selection.start_line or line > selection.end_line then
        return false
    end
    return true
end

function render_note_row(ix, last_note, last_volume)
    local track_index = rns.selected_track_index
    local note_column_index = ix
    local line_count = rns.selected_pattern.number_of_lines
    local selection = rns.selection_in_pattern
    local is_selected = is_selected_column(track_index, note_column_index, selection)

    local track = rns.selected_pattern:track(track_index)

    for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
        local pad = PADS[ix - NOTE_COLUMN_VIEW_POS + 1][i - NOTE_STEP_VIEW_POS + 1]
        if i <= line_count and i > 0 then
            local line = track:line(i)
            local note_value = line:note_column(note_column_index).note_value
            local volume_value = line:note_column(note_column_index).volume_value
            if note_value < 120 then
                last_note = note_value % 12
                last_volume = volume_value
            elseif note_value == 120 then
                last_note = -1
                last_volume = 0
            end
            if last_note < 0 then
                pad[1] = 0.0
                pad[2] = 0.0
                pad[3] = 0.0
                if is_selected and is_selected_line(i, selection) then
                    pad[3] = pad[3] + 0.2
                end
            else
                pad[1] = last_note / 12.0
                pad[2] = 1.0
                if note_value < 120 then
                    if note_value < 120 and volume_value >= 128 then
                        pad[3] = 0.9
                    elseif note_value < 120 then
                        pad[3] = 0.1 + 0.8 * volume_value / 128
                    end
                else
                    if last_volume < 128 then
                        pad[3] = 0.1 + 0.1 * last_volume / 256
                    else
                        pad[3] = 0.2
                    end
                end
                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.5
                end
            end
        else
            pad[1] = 0.0
            pad[2] = 0.0
            pad[3] = 0.0
        end
    end
end

function render_drum_row(ix)
    local track_index = rns.selected_track_index
    local note_column_index = ix
    local color = rgb_to_hsv(rns:track(track_index).color)
    local line_count = rns.selected_pattern.number_of_lines
    local selection = rns.selection_in_pattern
    local is_selected = is_selected_column(track_index, note_column_index, selection)

    local track = rns.selected_pattern:track(track_index)

    for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
        local pad = PADS[ix - NOTE_COLUMN_VIEW_POS + 1][i - NOTE_STEP_VIEW_POS + 1]
        if i <= line_count and i > 0 then
            local line = track:line(i)
            local note_value = line:note_column(note_column_index).note_value
            local volume_value = line:note_column(note_column_index).volume_value
            if note_value >= 120 then
                pad[1] = 0.0
                pad[2] = 0.0
                pad[3] = 0.0
                if is_selected and is_selected_line(i, selection) then
                    pad[3] = pad[3] + 0.2
                end
            else
                pad[1] = color[1]
                pad[2] = 1.0

                if note_value < 120 and volume_value >= 128 then
                    pad[3] = 1.0
                elseif note_value < 120 then
                    pad[3] = 0.1 + 0.9 * volume_value / 128
                end

                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.2
                end
            end
        else
            pad[1] = 0.0
            pad[2] = 0.0
            pad[3] = 0.0
        end
    end
end

function get_selection()
    local selection = rns.selection_in_pattern
    if selection == nil then
        selection = {}
        selection.start_track = rns.selected_track_index
        selection.end_track = rns.selected_track_index
        selection.start_line = rns.selected_line_index
        selection.end_line = rns.selected_line_index
        selection.start_column = CURRENT_NOTE_COLUMN
        selection.end_column = CURRENT_NOTE_COLUMN
    end
    return selection
end

function set_selection(new_selection)
    local selection = new_selection

    rns.selected_track_index = selection.start_track

    if not (selection.start_line == 1 and selection.end_line == rns.selected_pattern.number_of_lines) then
        rns.selected_note_column_index = selection.start_column
        rns.selected_line_index = selection.start_line
    end

    if selection.start_track == selection.end_track and selection.start_column == selection.end_column and selection.start_line == selection.end_line then
        rns.selection_in_pattern = {}
    else
        rns.selection_in_pattern = selection
    end


end

function shift_selection(steps)
    local selection = get_selection()
    local line_count = rns.selected_pattern.number_of_lines
    local step_remap = table.create()

    if selection.end_line - selection.start_line == line_count - 1 then
        -- full pattern selected
        if steps > 0 then
            -- rotate right
            for i = 1, line_count - steps do
                step_remap[i] = steps;
            end
            for i = line_count - steps + 1, line_count do
                step_remap[i] = steps - line_count
            end
        else
            -- rotate left
            for i = 1, -steps do
                step_remap[i] = line_count + steps;
            end
            for i = -steps + 1, line_count do
                step_remap[i] = steps
            end
        end
    else
        if steps > 0 then
            -- shift right
            if selection.end_line + steps > line_count then
                return
            end
            for i = selection.start_line, selection.end_line do
                step_remap[i] = steps;
            end
            for i = selection.end_line + 1, selection.end_line + steps do
                step_remap[i] = -(selection.end_line - selection.start_line + 1)
            end
        else
            -- shift left
            if selection.start_line + steps < 1 then
                return
            end
            for i = selection.start_line, selection.end_line do
                step_remap[i] = steps;
            end
            for i = selection.start_line + steps, selection.start_line - 1 do
                step_remap[i] = selection.end_line - selection.start_line + 1
            end
        end
        selection.start_line = selection.start_line + steps
        selection.end_line = selection.end_line + steps
    end

    remap_selection(step_remap, nil)
    set_selection(selection)
    mark_as_dirty()
end

function get_nearest_note()
    local track = rns.selected_pattern:track(rns.selected_track_index)
    local line_count = rns.selected_pattern.number_of_lines
    local line_index = rns.selected_line_index
    local note_column_index = CURRENT_NOTE_COLUMN
    for i = 1, line_count do
        if line_index - i < 1 and line_index + i > line_count then
            return nil
        end
        if line_index - i >= 1 then
            local note_column = track:line(line_index - i):note_column(note_column_index)
            if note_column.note_value < 120 then
                return note_column
            end
        end
        if line_index + i <= line_count then
            local note_column = track:line(line_index + i):note_column(note_column_index)
            if note_column.note_value < 120 then
                return note_column
            end
        end
    end
end

function remap_selection(step_remap, row_remap)
    local seq_len = rns.transport.song_length.sequence + 1
    local current_seq_index = rns.selected_sequence_index
    local note_column_len = rns:track(rns.selected_track_index).visible_note_columns
    local pattern_copy_index = rns.sequencer:insert_new_pattern_at(seq_len)
    local pattern_copy = rns:pattern(pattern_copy_index)
    rns.selected_sequence_index = current_seq_index
    pattern_copy:copy_from(rns.selected_pattern)

    local line_count = rns.selected_pattern.number_of_lines
    local selection = rns.selection_in_pattern
    local not_whole_track_selected = selection == nil or selection.start_line ~= 1 or selection.end_line ~= line_count
    local track_index = rns.selected_track_index
    local row_remap_local = row_remap
    if row_remap_local == nil then
        row_remap_local = table.create()
        if selection == nil then
            row_remap_local[rns.selected_note_column_index] = 0;
        else
            for i = 1, note_column_len do
                if is_selected_column(rns.selected_track_index, i, selection) then
                    row_remap_local[i] = 0;
                end
            end
        end
    end

    for i = 1, note_column_len do
        if (not_whole_track_selected or is_selected_column(rns.selected_track_index, i, selection)) then
            local new_track_index = track_index
            local new_note_column_index
            if row_remap_local[i] ~= nil then
                new_note_column_index = i + row_remap_local[i]
            end
            if new_note_column_index ~= nil then
                local track = pattern_copy:track(track_index)
                local new_track = rns.selected_pattern:track(new_track_index)

                for j = 1, line_count do
                    local new_step_pos = j
                    if new_note_column_index >= 1 and new_note_column_index <= note_column_len and step_remap[j] ~= nil then
                        new_step_pos = new_step_pos + step_remap[j]
                        local line = track:line(j)
                        local new_line = new_track:line(new_step_pos)
                        local data = line:note_column(i)
                        local new_data = new_line:note_column(new_note_column_index)
                        new_data:copy_from(data)
                        --new_data.note_value = data.note_value
                        --new_data.instrument_value = data.instrument_value
                        --new_data.volume_value = data.volume_value
                        --new_data.panning_value = data.panning_value
                        --new_data.delay_value = data.delay_value
                        --new_data.effect_number_value = data.effect_number_value
                        --new_data.effect_amount_value = data.effect_amount_value
                    end
                end
            end
        end
    end
    rns.sequencer:delete_sequence_at(seq_len)
    mark_as_dirty()
end

function apply_to_selection(apply)
    local line_count = rns.selected_pattern.number_of_lines
    local note_column_len = rns:track(rns.selected_track_index).visible_note_columns
    local selection = rns.selection_in_pattern
    for i = 1, note_column_len do
        local track_index = rns.selected_track_index
        local note_column_index = i
        local is_selected = is_selected_column(track_index, note_column_index, selection)
        local track = rns.selected_pattern:track(track_index)

        for j = 1, line_count do
            local line = track:line(j)
            local data = line:note_column(note_column_index)
            if is_selected and is_selected_line(j, selection) then
                apply(data)
            end
        end
    end
    mark_as_dirty()
end

function ui_pad_press(row, column)
    UI_PAD_PROCESSED = false
    if MODE == MODE_OVERVIEW then
        local track_ix = PERFORM_TRACK_VIEW_POS + column - 1
        if track_ix >= 1 and track_ix <= rns.sequencer_track_count then
            if row == 1 then
                rns.selected_track_index = track_ix
            elseif row == 3 then
                if UI_SHIFT_PRESSED then
                    for i = 1, rns.sequencer_track_count do
                        if i ~= track_ix then
                            rns:track(i).solo_state = false
                        end
                    end
                    rns:track(track_ix):solo()
                else
                    rns:track(track_ix):solo()
                end
            elseif row == 4 then
                if rns:track(track_ix).mute_state == renoise.Track.MUTE_STATE_ACTIVE then
                    if UI_SHIFT_PRESSED then
                        rns:track(track_ix).mute_state = renoise.Track.MUTE_STATE_MUTED
                    else
                        rns:track(track_ix).mute_state = renoise.Track.MUTE_STATE_OFF
                    end
                else
                    rns:track(track_ix).mute_state = renoise.Track.MUTE_STATE_ACTIVE
                end
            end
            mark_as_dirty()
        end
    elseif MODE == MODE_PERFORM then
        local seq_ix = PERFORM_SEQUENCE_VIEW_POS + row - 1
        local track_ix = PERFORM_TRACK_VIEW_POS + column - 1
        if seq_ix >= 1 and seq_ix <= #rns.sequencer.pattern_sequence and track_ix >= 1 and track_ix <= rns.sequencer_track_count then
            if (not UI_SHIFT_PRESSED and UI_ALT_PRESSED) or UI_PAD_PRESSED_COUNT >= 1 then
                local source = rns:pattern(rns.sequencer:pattern(rns.selected_sequence_index)):track(rns.selected_track_index)
                local target = rns:pattern(rns.sequencer:pattern(seq_ix)):track(track_ix)
                target:copy_from(source)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
                local source = rns:pattern(rns.sequencer:pattern(rns.selected_sequence_index)):track(rns.selected_track_index)
                local target = rns:pattern(rns.sequencer:pattern(seq_ix)):track(track_ix)
                target:copy_from(source)
                source:clear()
                rns.selected_sequence_index = seq_ix
                rns.selected_track_index = track_ix
                mark_as_dirty()
            elseif UI_STEP_PRESSED then
                rns.sequencer:set_track_sequence_slot_is_muted(track_ix, seq_ix, not rns.sequencer:track_sequence_slot_is_muted(track_ix, seq_ix))
                mark_as_dirty()
            elseif UI_ALT_PRESSED and UI_SHIFT_PRESSED then
                local target = rns:pattern(rns.sequencer:pattern(seq_ix)):track(track_ix)
                target:clear()
                mark_as_dirty()
            elseif not UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
                rns.selected_sequence_index = seq_ix
                rns.selected_track_index = track_ix
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local row_ix = NOTE_COLUMN_VIEW_POS + row - 1
        local column_ix = NOTE_STEP_VIEW_POS + column - 1

        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            local track = rns.selected_pattern:track(rns.selected_track_index)
            local line_count = rns.selected_pattern.number_of_lines
            if column_ix + 1 <= line_count then
                local note_column = track:line(column_ix + 1):note_column(row_ix)
                if note_column.note_value == 120 then
                    note_column.note_value = 121
                elseif note_column.note_value == 121 then
                    note_column.note_value = 120
                end
            end

            -- clean following OFFs
            for i = column_ix, 1, -1 do
                local note_column = track:line(i):note_column(row_ix)
                if note_column.note_value == 120 then
                    note_column.note_value = 121
                elseif note_column.note_value < 120 then
                    break
                end
            end
            if column_ix + 1 <= line_count and track:line(column_ix + 1):note_column(row_ix).note_value >= 120 then
                for i = column_ix + 2, line_count do
                    local note_column = track:line(i):note_column(row_ix)
                    if note_column.note_value == 120 then
                        note_column.note_value = 121
                    elseif note_column.note_value < 120 then
                        break
                    end
                end
            end
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            if is_selected_column(rns.selected_track_index, row_ix, rns.selection_in_pattern) and is_selected_line(column_ix, rns.selection_in_pattern) then
                apply_to_selection(function(note_column)
                    note_column:clear()
                end)
            end
            UI_PAD_PROCESSED = true
        elseif UI_SHIFT_PRESSED or UI_PAD_PRESSED_COUNT >= 1 then
            local start_line = rns.selected_line_index
            local start_track = rns.selected_track_index
            local start_column = CURRENT_NOTE_COLUMN
            local end_line = column_ix
            local end_track = rns.selected_track_index
            local end_column = row_ix

            if start_line > end_line then
                start_line = column_ix
                end_line = rns.selected_line_index
            end
            if start_column > end_column then
                start_column = row_ix
                end_column = CURRENT_NOTE_COLUMN
            end

            -- expand end column if needed
            if rns:track(end_track).visible_note_columns == end_column then
                end_column = end_column + rns:track(end_track).visible_effect_columns
            end

            rns.selection_in_pattern = {
                start_line = start_line,
                start_column = start_column,
                start_track = start_track,
                end_line = end_line,
                end_column = end_column,
                end_track = end_track
            }
            UI_PAD_PROCESSED = true
        elseif UI_ALT_PRESSED then
            local selection = get_selection()
            local selected_row = selection.start_column
            local row_remap = table.create()
            for i = selection.start_column, selection.end_column do
                row_remap[i] = row_ix - selected_row
            end
            local step_diff = column_ix - selection.start_line
            local step_remap = table.create()
            for i = selection.start_line, selection.end_line do
                step_remap[i] = step_diff
            end
            remap_selection(step_remap, row_remap)
            mark_as_dirty()
            UI_PAD_PROCESSED = true
        elseif row_ix <= rns:track(rns.selected_track_index).visible_note_columns and column_ix <= rns.selected_pattern.number_of_lines then
            rns.selection_in_pattern = {}

            rns.selected_note_column_index = row_ix
            rns.selected_line_index = column_ix
        end

        mark_as_dirty()
    end

    UI_PAD_PRESSED_COUNT = UI_PAD_PRESSED_COUNT + 1
end

function ui_pad_release(row, column)
    local row_ix = NOTE_COLUMN_VIEW_POS + row - 1
    local column_ix = NOTE_STEP_VIEW_POS + column - 1

    if row_ix <= rns:track(rns.selected_track_index).visible_note_columns and column_ix <= rns.selected_pattern.number_of_lines then
        if MODE == MODE_DRUM and not UI_PAD_PROCESSED then
            local track = rns.selected_pattern:track(rns.selected_track_index)
            local note_column = track:line(rns.selected_line_index):note_column(row_ix)
            if note_column.note_value < 120 then
                note_column:clear()
            else
                local nearest_note = get_nearest_note()
                if nearest_note ~= nil then
                    note_column:clear()
                    note_column.note_value = nearest_note.note_value
                    note_column.instrument_value = nearest_note.instrument_value
                    UI_PAD_PROCESSED = true
                end
            end
        end
    end
    UI_PAD_PRESSED_COUNT = UI_PAD_PRESSED_COUNT - 1
end

function ui_step_press()
    UI_STEP_PRESSED = true
    UI_STEP_PROCESSED = false
    ui_update_nav_buttons()
    ui_update_state_buttons()
    if MODE == MODE_DRUM then
        mark_as_dirty()
    end
end

function ui_step_release()
    UI_STEP_PRESSED = false
    if not UI_STEP_PROCESSED and (MODE == MODE_NOTE or MODE == MODE_DRUM) then
        local line_count = rns.selected_pattern.number_of_lines
        local new_line
        if UI_SHIFT_PRESSED then
            new_line = rns.selected_line_index - rns.transport.edit_step
        else
            new_line = rns.selected_line_index + rns.transport.edit_step
        end
        if new_line > line_count then
            new_line = new_line - line_count
        end
        if new_line < 1 then
            new_line = new_line + line_count
        end
        if new_line >= 1 and new_line <= line_count then
            rns.selected_line_index = new_line
        end
    end
    if MODE == MODE_DRUM then
        mark_as_dirty()
    end
    ui_update_nav_buttons()
    ui_update_state_buttons()
end

function ui_shift_press()
    UI_SHIFT_PRESSED = true
    ui_update_nav_buttons()
    ui_update_state_buttons()
end

function ui_shift_release()
    UI_SHIFT_PRESSED = false
    ui_update_nav_buttons()
    ui_update_state_buttons()
end

function ui_alt_press()
    UI_ALT_PRESSED = true
    ui_update_nav_buttons()
    ui_update_state_buttons()
end

function ui_alt_release()
    UI_ALT_PRESSED = false
    ui_update_nav_buttons()
    ui_update_state_buttons()
end

function ui_browse_press()
    UI_BROWSE_PRESSED = not UI_BROWSE_PRESSED
    if UI_BROWSE_PRESSED then
        renoise.app().window.disk_browser_is_visible = true
        renoise.app().window.instrument_box_is_visible = true
        if rns:instrument(rns.selected_instrument_index).plugin_properties.plugin_loaded then
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
        else
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
        end
    else
        if MODE == MODE_PERFORM then
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        elseif MODE == MODE_OVERVIEW then
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
        elseif MODE == MODE_DRUM or MODE == MODE_NOTE then
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        end
    end
    ui_update_state_buttons()
end

function ui_grid_next()
    local line_count = rns.selected_pattern.number_of_lines
    local track_count = rns.sequencer_track_count
    local column_num = rns:track(rns.selected_track_index).visible_note_columns
    if MODE == MODE_PERFORM or MODE == MODE_OVERVIEW then
        if PERFORM_TRACK_VIEW_POS + PAD_COLUMNS <= track_count then
            PERFORM_TRACK_VIEW_POS = PERFORM_TRACK_VIEW_POS + 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local is_not_last = NOTE_STEP_VIEW_POS + PAD_COLUMNS < rns.selected_pattern.number_of_lines
        local selection = get_selection()
        local is_whole_track_selected = selection.start_line == 1 and selection.end_line == line_count
        if is_not_last and UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            if is_whole_track_selected then
                for i = 1, column_num do
                    if is_selected_column(rns.selected_track_index, i, selection) then
                        for j = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                            rns.selected_pattern:track(rns.selected_track_index):line(j):note_column(i):clear()
                        end
                    end
                end
            else
                for j = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                    rns.selected_pattern:track(rns.selected_track_index):line(j):clear()
                end
            end
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        elseif is_not_last and UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                step_remap[i] = PAD_COLUMNS
            end
            for i = NOTE_STEP_VIEW_POS + PAD_COLUMNS, NOTE_STEP_VIEW_POS + PAD_COLUMNS * 2 - 1 do
                step_remap[i] = -PAD_COLUMNS
            end
            remap_selection(step_remap, nil)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        elseif is_not_last and UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                step_remap[i] = PAD_COLUMNS
            end
            remap_selection(step_remap, nil)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        elseif is_not_last then
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        end
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_grid_prev()
    local line_count = rns.selected_pattern.number_of_lines
    local column_num = rns:track(rns.selected_track_index).visible_note_columns
    if MODE == MODE_PERFORM or MODE == MODE_OVERVIEW then
        if PERFORM_TRACK_VIEW_POS > 1 then
            PERFORM_TRACK_VIEW_POS = PERFORM_TRACK_VIEW_POS - 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local is_not_first = NOTE_STEP_VIEW_POS > PAD_COLUMNS
        local selection = get_selection()
        local is_whole_track_selected = selection.start_line == 1 and selection.end_line == line_count
        if is_not_first and UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            if is_whole_track_selected then
                for i = 1, column_num do
                    if is_selected_column(rns.selected_track_index, i, selection) then
                        for j = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                            rns.selected_pattern:track(rns.selected_track_index):line(j):note_column(i):clear()
                        end
                    end
                end
            else
                for j = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                    rns.selected_pattern:track(rns.selected_track_index):line(j):clear()
                end
            end
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        elseif is_not_first and UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                step_remap[i] = -PAD_COLUMNS
            end
            for i = NOTE_STEP_VIEW_POS - PAD_COLUMNS, NOTE_STEP_VIEW_POS - 1 do
                step_remap[i] = PAD_COLUMNS
            end
            remap_selection(step_remap, nil)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        elseif is_not_first and UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do
                step_remap[i] = -PAD_COLUMNS
            end
            remap_selection(step_remap, nil)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        elseif is_not_first then
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        end
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_pattern_prev()
    if MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS > 1 then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS - 1
            rns.sequencer.selection_range = { PERFORM_SEQUENCE_VIEW_POS, PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS - 1 }
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local track_index = rns.selected_track_index
            if track_index > 1 then
                rns.selected_track_index = track_index - 1
                ui_update_nav_buttons()
            end
        elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            local track_index = rns.selected_track_index
            rns:insert_track_at(track_index)
            rns.selected_track_index = track_index
            mark_as_dirty()
            ui_update_nav_buttons()
        elseif UI_ALT_PRESSED and UI_SHIFT_PRESSED and rns.sequencer_track_count > 1 and rns.selected_track_index > 1 then
            local track_index = rns.selected_track_index
            rns:delete_track_at(track_index)
            rns.selected_track_index = track_index - 1
            mark_as_dirty()
            ui_update_nav_buttons()
        else
            if NOTE_COLUMN_VIEW_POS > 1 then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS - 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_pattern_next()
    local column_num = rns:track(rns.selected_track_index).visible_note_columns
    local seq_len = rns.transport.song_length.sequence

    if MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS + 1
            rns.sequencer.selection_range = { PERFORM_SEQUENCE_VIEW_POS, PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS - 1 }
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local track_index = rns.selected_track_index
            if track_index < rns.sequencer_track_count then
                rns.selected_track_index = track_index + 1
                ui_update_nav_buttons()
            end
        elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            local track_index = rns.selected_track_index
            rns:insert_track_at(track_index + 1)
            rns.selected_track_index = track_index + 1
            mark_as_dirty()
            ui_update_nav_buttons()
        elseif UI_ALT_PRESSED and UI_SHIFT_PRESSED and rns.sequencer_track_count > 1 and rns.selected_track_index < rns.sequencer_track_count then
            local track_index = rns.selected_track_index
            rns:delete_track_at(track_index)
            mark_as_dirty()
            ui_update_nav_buttons()
        else
            if NOTE_COLUMN_VIEW_POS + PAD_ROWS <= column_num then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS + 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_select_prev()
    if UI_MODE_PRESSED then
        if rns:can_undo() then
            rns:undo()
        end
    elseif UI_BROWSE_PRESSED then
        if rns.selected_instrument_index > 1 then
            rns.selected_instrument_index = rns.selected_instrument_index - 1
            if rns:instrument(rns.selected_instrument_index).plugin_properties.plugin_loaded then
                renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
            else
                renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
            end
        end
    elseif MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS > 1 then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS - 1
            rns.sequencer.selection_range = { math.max(1,PERFORM_SEQUENCE_VIEW_POS), math.min(PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS - 1, #rns.sequencer.pattern_sequence) }
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            if rns.transport.edit_step > 0 then
                rns.transport.edit_step = rns.transport.edit_step - 1
            end
        elseif UI_ALT_PRESSED then
            apply_to_selection(function(column)
                if column.instrument_value > 0 and column.note_value < 120 then
                    column.instrument_value = column.instrument_value - 1
                end
            end)
        elseif UI_SHIFT_PRESSED then
            shift_selection(-1)
        else
            apply_to_selection(function(column)
                if column.note_value > 1 and column.note_value < 120 then
                    column.note_value = column.note_value - 1
                end
            end)
        end
    end
end

function ui_select_next()
    local seq_len = rns.transport.song_length.sequence
    if UI_MODE_PRESSED then
        if rns:can_redo() then
            rns:redo()
        end
    elseif UI_BROWSE_PRESSED then
        if rns.selected_instrument_index < #rns.instruments then
            rns.selected_instrument_index = rns.selected_instrument_index + 1
            if rns:instrument(rns.selected_instrument_index).plugin_properties.plugin_loaded then
                renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
            else
                renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
            end
        end
    elseif MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS + 1
            rns.sequencer.selection_range = { PERFORM_SEQUENCE_VIEW_POS, PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS - 1 }
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            if rns.transport.edit_step < 64 then
                rns.transport.edit_step = rns.transport.edit_step + 1
            end
        elseif UI_ALT_PRESSED then
            apply_to_selection(function(column)
                if column.instrument_value < #rns.instruments - 1 and column.note_value < 120 then
                    column.instrument_value = column.instrument_value + 1
                end
            end)
        elseif UI_SHIFT_PRESSED then
            shift_selection(1)
        else
            apply_to_selection(function(column)
                if column.note_value < 120 - 1 then
                    column.note_value = column.note_value + 1
                end
            end)
        end
    end
end

function ui_row_select(index)
    if MODE == MODE_OVERVIEW then
        if index == 1 then
            for i = 1, rns.sequencer_track_count do
                rns:track(i).solo_state = false
                rns:track(i).mute_state = renoise.Track.MUTE_STATE_ACTIVE
            end
        elseif index == 3 then
            for i = 1, rns.sequencer_track_count do
                rns:track(i).solo_state = false
            end
        elseif index == 4 then
            for i = 1, rns.sequencer_track_count do
                rns:track(i).mute_state = renoise.Track.MUTE_STATE_ACTIVE
            end
        end
        mark_as_dirty()
    elseif MODE == MODE_PERFORM then
        local seq_ix = PERFORM_SEQUENCE_VIEW_POS + index - 1
        if seq_ix >= 1 and seq_ix <= #rns.sequencer.pattern_sequence then
            if not UI_SHIFT_PRESSED and not UI_ALT_PRESSED and not UI_STEP_PRESSED then
                rns.transport:set_scheduled_sequence(seq_ix)
                PLAYBACK_NEXT_SEQUENCE = seq_ix
                mark_as_dirty()
            elseif not UI_SHIFT_PRESSED and not UI_ALT_PRESSED and UI_STEP_PRESSED then
                local songpos = rns.transport.playback_pos
                songpos.sequence = seq_ix
                xPatternSequencer.switch_to_sequence(songpos)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and not UI_ALT_PRESSED and not UI_STEP_PRESSED then
                if seq_ix < PLAYBACK_NEXT_SEQUENCE then
                    PLAYBACK_NEXT_SEQUENCE = PLAYBACK_NEXT_SEQUENCE + 1
                end
                rns.sequencer:insert_new_pattern_at(seq_ix + 1)
                local target = rns:pattern(rns.sequencer:pattern(seq_ix + 1))
                target:clear()
                mark_as_dirty()
            elseif not UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
                if seq_ix < PLAYBACK_NEXT_SEQUENCE then
                    PLAYBACK_NEXT_SEQUENCE = PLAYBACK_NEXT_SEQUENCE + 1
                end
                local source = rns:pattern(rns.sequencer:pattern(seq_ix))
                rns.sequencer:insert_new_pattern_at(seq_ix + 1)
                local target = rns:pattern(rns.sequencer:pattern(seq_ix + 1))
                target:copy_from(source)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
                if seq_ix == PLAYBACK_NEXT_SEQUENCE then
                    PLAYBACK_NEXT_SEQUENCE = -1
                elseif seq_ix < PLAYBACK_NEXT_SEQUENCE then
                    PLAYBACK_NEXT_SEQUENCE = PLAYBACK_NEXT_SEQUENCE - 1
                end
                if #rns.sequencer.pattern_sequence > 1 then
                    rns.sequencer:delete_sequence_at(seq_ix)
                    mark_as_dirty()
                end
            end
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local track = rns.selected_pattern:track(rns.selected_track_index)
        local column_num = rns:track(rns.selected_track_index).visible_note_columns

        if UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            if NOTE_COLUMN_VIEW_POS + index - 1 <= column_num then
                -- swap note columns
                local row_remap = table.create()
                local step_remap = table.create()
                for i = 1, rns.selected_pattern.number_of_lines do
                    step_remap[i] = 0;
                end
                rns.selection_in_pattern = nil
                local diff = NOTE_COLUMN_VIEW_POS + index - 1 - rns.selected_note_column_index
                row_remap[NOTE_COLUMN_VIEW_POS + index - 1] = -diff;
                row_remap[rns.selected_note_column_index] = diff;
                remap_selection(step_remap, row_remap)
            end
        elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            -- insert after
            local ix = math.min(NOTE_COLUMN_VIEW_POS + index - 1, column_num)
            rns:track(rns.selected_track_index).visible_note_columns = column_num + 1
            for j = 1, rns.selected_pattern.number_of_lines do
                for i = column_num, ix, -1 do
                    track:line(j):note_column(i + 1):copy_from(track:line(j):note_column(i))
                end
            end
            if rns.selected_note_column_index > ix then
                rns.selected_note_column_index = rns.selected_note_column_index + 1
                focus_note_column()
            end
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED and NOTE_COLUMN_VIEW_POS + index - 1 <= column_num and column_num > 1 then
            local ix = NOTE_COLUMN_VIEW_POS + index - 1
            -- Check if it's possible to delete note_column
            local is_empty = true
            for _, line in rns.pattern_iterator:lines_in_track(rns.selected_track_index, true) do
                if not line:note_column(ix).is_empty then
                    is_empty = false
                    break
                end
            end
            if is_empty then
                for j = 1, rns.selected_pattern.number_of_lines do
                    for i = ix, column_num - 1 do
                        track:line(j):note_column(i):copy_from(track:line(j):note_column(i + 1))
                    end
                    track:line(j):note_column(column_num):clear()
                end
                rns:track(rns.selected_track_index).visible_note_columns = column_num - 1
                if rns.selected_note_column_index > ix then
                    rns.selected_note_column_index = rns.selected_note_column_index - 1
                    focus_note_column()
                end
            else
                for j = 1, rns.selected_pattern.number_of_lines do
                    track:line(j):note_column(ix):clear()
                end
            end
        elseif NOTE_COLUMN_VIEW_POS + index - 1 <= column_num then
            local start_line = 1
            local start_track = rns.selected_track_index
            local start_column = NOTE_COLUMN_VIEW_POS + index - 1
            local end_line = rns.selected_pattern.number_of_lines
            local end_track = rns.selected_track_index
            local end_column = NOTE_COLUMN_VIEW_POS + index - 1
            local selection = rns.selection_in_pattern

            if selection ~= nil then
                if selection.start_line == start_line and selection.end_line == end_line and is_selected_column(start_track, start_column, selection) then
                    if selection.start_column == 1 and selection.end_column >= rns:track(end_track).visible_note_columns then
                        rns.selection_in_pattern = {}
                        mark_as_dirty()
                        return
                    end
                    start_column = nil
                    end_column = nil
                end
            end

            set_selection({
                start_line = start_line,
                start_column = start_column,
                start_track = start_track,
                end_line = end_line,
                end_column = end_column,
                end_track = end_track
            })

            rns.selected_note_column_index = NOTE_COLUMN_VIEW_POS + index - 1
        end
    end
    mark_as_dirty()
end

function ui_note_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        rns.transport.record_quantize_enabled = not rns.transport.record_quantize_enabled
        ui_update_transport_buttons()
        mark_as_dirty()
    elseif rns:track(rns.selected_track_index).type == renoise.Track.TRACK_TYPE_SEQUENCER then
        UI_BROWSE_PRESSED = false
        MODE = MODE_NOTE
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        ui_update_nav_buttons()
        ui_update_state_buttons()
        mark_as_dirty()
    end
end

function ui_drum_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        local new_loop_block_enabled = not rns.transport.loop_block_enabled
        rns.transport.loop_block_enabled = new_loop_block_enabled
        ui_update_transport_buttons(new_loop_block_enabled)
        mark_as_dirty()
    elseif rns:track(rns.selected_track_index).type == renoise.Track.TRACK_TYPE_SEQUENCER then
        UI_BROWSE_PRESSED = false
        MODE = MODE_DRUM
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        ui_update_nav_buttons()
        ui_update_state_buttons()
        mark_as_dirty()
    end
end

function ui_perform_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        UI_BROWSE_PRESSED = false
        MODE = MODE_OVERVIEW
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
        ui_update_nav_buttons()
        ui_update_state_buttons()
        mark_as_dirty()
    elseif UI_BROWSE_PRESSED and (MODE == MODE_PERFORM or MODE == MODE_OVERVIEW) then
        ui_browse_press()
    else
        if MODE == MODE_PERFORM and not UI_BROWSE_PRESSED then
            UI_BROWSE_PRESSED = false
            MODE = MODE_OVERVIEW
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
        else
            UI_BROWSE_PRESSED = false
            MODE = MODE_PERFORM
            renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        end
        ui_update_nav_buttons()
        ui_update_state_buttons()
        mark_as_dirty()
    end
end

function ui_song_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        rns.transport.metronome_enabled = not rns.transport.metronome_enabled
    else
        rns.transport.loop_pattern = not rns.transport.loop_pattern
    end
    ui_update_transport_buttons()
    mark_as_dirty()
end

function ui_play_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        rns.transport:start(renoise.Transport.PLAYMODE_CONTINUE_PATTERN)
    else
        rns.transport:start(renoise.Transport.PLAYMODE_RESTART_PATTERN)
    end
end

function ui_stop_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        rns.transport.metronome_precount_enabled = not rns.transport.metronome_precount_enabled
        ui_update_transport_buttons()
        mark_as_dirty()
    else
        rns.transport:stop()
    end
end

function ui_rec_press()
    if UI_ALT_PRESSED then
        return
    end
    if UI_SHIFT_PRESSED then
        rns.transport.follow_player = not rns.transport.follow_player
        ui_update_transport_buttons()
        mark_as_dirty()
    else
        rns.transport.edit_mode = not rns.transport.edit_mode
    end
end

function interpolate(volume, panning)
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        local line_count = rns.selected_pattern.number_of_lines
        local column_num = rns:track(rns.selected_track_index).visible_note_columns
        local selection = rns.selection_in_pattern
        for i = 1, column_num do
            local track_index = rns.selected_track_index
            local note_column_index = i
            local is_selected = is_selected_column(track_index, note_column_index, selection)
            local track = rns.selected_pattern:track(track_index)

            local start_line = selection.start_line
            local end_line = selection.end_line

            local len = end_line - start_line

            local start_note = track:line(start_line):note_column(note_column_index)
            local end_note = track:line(end_line):note_column(note_column_index)

            local int_volume = volume and start_note.volume_value < 128 and end_note.volume_value < 128
            local int_panning = panning and start_note.panning_value < 128 and end_note.panning_value < 128

            local start_volume = start_note.volume_value
            local start_panning = start_note.panning_value

            local end_volume = end_note.volume_value
            local end_panning = end_note.panning_value

            for j = 1, line_count do
                local line = track:line(j)
                local data = line:note_column(note_column_index)
                if is_selected and is_selected_line(j, selection) then
                    if int_volume then
                        data.volume_value = start_volume + (end_volume - start_volume) / len * (j - start_line)
                    end
                    if int_panning then
                        data.panning_value = start_panning + (end_panning - start_panning) / len * (j - start_line)
                    end
                end
            end
        end
    end
end

function ui_mode_press()
    UI_MODE_PRESSED = true
end

function ui_mode_release()
    UI_MODE_PRESSED = false
end

function ui_knob1_touch()
    if MODE == MODE_DRUM or MODE == MODE_NOTE then
        if UI_MODE_PRESSED then
            interpolate(true, false)
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data)
                data.volume_string = '..'
            end)
        end
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    end
end

function ui_knob2_touch()
    if MODE == MODE_DRUM or MODE == MODE_NOTE then
        if UI_MODE_PRESSED then
            interpolate(false, true)
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data)
                data.panning_string = '..'
            end)
        end
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    end
end

function ui_knob3_touch()
    if MODE == MODE_DRUM or MODE == MODE_NOTE then
        if UI_MODE_PRESSED then
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data)
                data.delay_string = '..'
            end)
        end
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    end
end

function ui_knob4_touch()
    -- noop
end

function ui_knob1(value)
    if UI_SHIFT_PRESSED and UI_ALT_PRESSED then
        return
    end
    if MODE == MODE_DRUM or MODE == MODE_NOTE and not UI_MODE_PRESSED then
        rns:track(rns.selected_track_index).volume_column_visible = true
        apply_to_selection(function(data)
            local old_value = data.volume_value
            if data.volume_string == '..' then
                old_value = 0x7f
            end
            local new_value = math.min(math.max(old_value + value, 0), 0x7f)
            data.volume_value = new_value
        end)
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    elseif (MODE == MODE_PERFORM or MODE == MODE_OVERVIEW) and not UI_MODE_PRESSED then
        local old_value = 200 * rns:track(rns.selected_track_index).postfx_volume.value
        local new_value = math.min(math.max(old_value + value, 0), 200 * 1.4125375747681)
        rns:track(rns.selected_track_index).postfx_volume.value = new_value / 200
        mark_as_dirty()
    end
end

function ui_knob2(value)
    if UI_SHIFT_PRESSED and UI_ALT_PRESSED then
        return
    end
    if MODE == MODE_DRUM or MODE == MODE_NOTE and not UI_MODE_PRESSED then
        rns:track(rns.selected_track_index).panning_column_visible = true
        apply_to_selection(function(data)
            local old_value = data.panning_value
            if data.panning_string == '..' then
                old_value = 0x40
            end
            local new_value = math.min(math.max(old_value + value, 0), 0x7f)
            data.panning_value = new_value
        end)
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    elseif (MODE == MODE_PERFORM or MODE == MODE_OVERVIEW) and not UI_MODE_PRESSED then
        local old_value = 200 * rns:track(rns.selected_track_index).postfx_panning.value
        local new_value = math.min(math.max(old_value + value, 0), 200)
        rns:track(rns.selected_track_index).postfx_panning.value = new_value / 200
        mark_as_dirty()
    end
end

function ui_knob3(value)
    if UI_SHIFT_PRESSED and UI_ALT_PRESSED then
        return
    end
    if MODE == MODE_DRUM or MODE == MODE_NOTE and not UI_MODE_PRESSED then
        rns:track(rns.selected_track_index).delay_column_visible = true
        apply_to_selection(function(data)
            local old_value = data.delay_value
            if data.delay_string == '..' then
                old_value = 0
            end
            local new_value = math.min(math.max(old_value + value, 0), 0x7f)
            data.delay_value = new_value
        end)
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    end
end

function ui_knob4(value)
    if UI_SHIFT_PRESSED and UI_ALT_PRESSED then
        return
    end
    if MODE == MODE_DRUM or MODE == MODE_NOTE and not UI_MODE_PRESSED then
        local old_color = rgb_to_hsv(rns:track(rns.selected_track_index).color)
        local old_value = 256 * old_color[1]
        local new_value = old_value + value
        if new_value < 0 then
            new_value = new_value + 256
        elseif new_value > 256 then
            new_value = new_value - 256
        end
        rns:track(rns.selected_track_index).color = hsv_to_rgb({ new_value / 256, 1.0, 1.0 })
        UI_PAD_PROCESSED = true
        mark_as_dirty()
    elseif (MODE == MODE_PERFORM or MODE == MODE_OVERVIEW) and not UI_MODE_PRESSED then
        local cell = rns:track(rns.selected_track_index)
        local old_color = rgb_to_hsv(cell.color)

        local old_value = 256 * old_color[1]
        local new_value = old_value + value
        if new_value < 0 then
            new_value = new_value + 256
        elseif new_value > 256 then
            new_value = new_value - 256
        end
        cell.color = hsv_to_rgb({ new_value / 256, 1.0, 1.0 })
        mark_as_dirty()
    end
end

function ui_select(value)
    if value > 0 then
        ui_select_next()
    else
        ui_select_prev()
    end
end

function ui_update_note_buttons()
    if MODE == MODE_NOTE then
        midi_note(COLOR_RED)
        midi_drum(COLOR_OFF)
        midi_perform(COLOR_OFF)
    elseif MODE == MODE_DRUM then
        midi_note(COLOR_OFF)
        midi_drum(COLOR_RED)
        midi_perform(COLOR_OFF)
    end

    if UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
        if rns.selected_track_index > 1 then
            midi_pattern_prev(COLOR_RED_LOW)
        else
            midi_pattern_prev(COLOR_OFF)
        end
        if rns.selected_track_index < rns.sequencer_track_count then
            midi_pattern_next(COLOR_RED_LOW)
        else
            midi_pattern_next(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS > 1 then
            midi_grid_prev(COLOR_RED_LOW)
        else
            midi_grid_prev(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS + PAD_COLUMNS <= rns.selected_pattern.number_of_lines then
            midi_grid_next(COLOR_RED_LOW)
        else
            midi_grid_next(COLOR_OFF)
        end
    elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
        midi_pattern_prev(COLOR_RED_LOW)
        midi_pattern_next(COLOR_RED_LOW)
        midi_grid_prev(COLOR_RED_LOW)
        if NOTE_STEP_VIEW_POS > 1 then
            midi_grid_prev(COLOR_RED_LOW)
        else
            midi_grid_prev(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS + PAD_COLUMNS <= rns.selected_pattern.number_of_lines then
            midi_grid_next(COLOR_RED_LOW)
        else
            midi_grid_next(COLOR_OFF)
        end
    elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
        if rns.sequencer_track_count > 1 then
            if rns.selected_track_index > 1 then
                midi_pattern_prev(COLOR_RED_LOW)
            else
                midi_pattern_prev(COLOR_OFF)
            end
            if rns.selected_track_index < rns.sequencer_track_count then
                midi_pattern_next(COLOR_RED_LOW)
            else
                midi_pattern_next(COLOR_OFF)
            end
        else
            midi_pattern_prev(COLOR_OFF)
            midi_pattern_next(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS > 1 and rns.selected_pattern.number_of_lines > PAD_COLUMNS then
            midi_grid_prev(COLOR_RED_LOW)
        else
            midi_grid_prev(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS + PAD_COLUMNS <= rns.selected_pattern.number_of_lines and rns.selected_pattern.number_of_lines > PAD_COLUMNS then
            midi_grid_next(COLOR_RED_LOW)
        else
            midi_grid_next(COLOR_OFF)
        end
    else
        if NOTE_COLUMN_VIEW_POS > 1 then
            midi_pattern_prev(COLOR_RED_LOW)
        else
            midi_pattern_prev(COLOR_OFF)
        end
        if NOTE_COLUMN_VIEW_POS < rns:track(rns.selected_track_index).visible_note_columns - PAD_ROWS + 1 then
            midi_pattern_next(COLOR_RED_LOW)
        else
            midi_pattern_next(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS > 1 then
            midi_grid_prev(COLOR_RED_LOW)
        else
            midi_grid_prev(COLOR_OFF)
        end
        if NOTE_STEP_VIEW_POS + PAD_COLUMNS <= rns.selected_pattern.number_of_lines then
            midi_grid_next(COLOR_RED_LOW)
        else
            midi_grid_next(COLOR_OFF)
        end
    end
end

function ui_update_perform_buttons()
    local seq_len = rns.transport.song_length.sequence

    if rns:track(rns.selected_track_index).type == renoise.Track.TRACK_TYPE_SEQUENCER then
        midi_note(COLOR_OFF)
        midi_drum(COLOR_OFF)
    else
        midi_note(COLOR_OFF)
        midi_drum(COLOR_OFF)
    end
    midi_perform(COLOR_RED)

    if PERFORM_TRACK_VIEW_POS > 1 then
        midi_grid_prev(COLOR_RED_LOW)
    else
        midi_grid_prev(COLOR_OFF)
    end
    if PERFORM_TRACK_VIEW_POS + PAD_COLUMNS <= rns.sequencer_track_count then
        midi_grid_next(COLOR_RED_LOW)
    else
        midi_grid_next(COLOR_OFF)
    end
    if PERFORM_SEQUENCE_VIEW_POS > 1 then
        midi_pattern_prev(COLOR_RED_LOW)
    else
        midi_pattern_prev(COLOR_OFF)
    end
    if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
        midi_pattern_next(COLOR_RED_LOW)
    else
        midi_pattern_next(COLOR_OFF)
    end

end

function ui_update_overview_buttons()

    if rns:track(rns.selected_track_index).type == renoise.Track.TRACK_TYPE_SEQUENCER then
        midi_note(COLOR_OFF)
        midi_drum(COLOR_OFF)
    else
        midi_note(COLOR_OFF)
        midi_drum(COLOR_OFF)
    end
    midi_perform(COLOR_YELLOW)

    if PERFORM_TRACK_VIEW_POS > 1 then
        midi_grid_prev(COLOR_RED_LOW)
    else
        midi_grid_prev(COLOR_OFF)
    end
    if PERFORM_TRACK_VIEW_POS + PAD_COLUMNS <= rns.sequencer_track_count then
        midi_grid_next(COLOR_RED_LOW)
    else
        midi_grid_next(COLOR_OFF)
    end

    midi_pattern_prev(COLOR_OFF)
    midi_pattern_next(COLOR_OFF)
end

function ui_update_nav_buttons()
    -- grid prev/next
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        ui_update_note_buttons()
    elseif MODE == MODE_PERFORM then
        ui_update_perform_buttons()
    elseif MODE == MODE_OVERVIEW then
        ui_update_overview_buttons()
    end

    ui_update_transport_buttons()
end

function ui_update_transport_buttons(new_loop_block_enabled)
    if UI_ALT_PRESSED then
        midi_rec(COLOR_OFF)
        midi_play(COLOR_OFF)
        midi_stop(COLOR_OFF)
        midi_song(COLOR_OFF)
        midi_perform(COLOR_OFF)
        midi_drum(COLOR_OFF)
        midi_note(COLOR_OFF)
    elseif UI_SHIFT_PRESSED then
        if rns.transport.playing then
            midi_play(COLOR_GREEN)
        else
            midi_play(COLOR_OFF)
        end
        if rns.transport.follow_player then
            midi_rec(COLOR_YELLOW)
        else
            midi_rec(COLOR_OFF)
        end
        if rns.transport.metronome_precount_enabled then
            midi_stop(COLOR_YELLOW)
        else
            midi_stop(COLOR_OFF)
        end
        if rns.transport.metronome_enabled then
            midi_song(COLOR_YELLOW)
        else
            midi_song(COLOR_OFF)
        end
        if (new_loop_block_enabled == nil and rns.transport.loop_block_enabled) or new_loop_block_enabled then
            midi_drum(COLOR_YELLOW)
        else
            midi_drum(COLOR_OFF)
        end
        if rns.transport.record_quantize_enabled then
            midi_note(COLOR_YELLOW)
        else
            midi_note(COLOR_OFF)
        end
    else
        if rns.transport.loop_pattern then
            midi_song(COLOR_OFF)
        else
            midi_song(COLOR_GREEN)
        end

        if rns.transport.playing then
            midi_play(COLOR_GREEN)
            midi_stop(COLOR_OFF)
        else
            midi_play(COLOR_OFF)
            midi_stop(COLOR_YELLOW)
        end

        if rns.transport.edit_mode then
            midi_rec(COLOR_RED)
        else
            midi_rec(COLOR_OFF)
        end
    end

    mark_as_dirty()
end

function ui_update_state_buttons()
    if UI_BROWSE_PRESSED then
        midi_browse(COLOR_RED)
    else
        midi_browse(COLOR_OFF)
    end

    if UI_STEP_PRESSED then
        midi_step(COLOR_YELLOW)
    else
        midi_step(COLOR_OFF)
    end

    if UI_SHIFT_PRESSED then
        midi_shift(COLOR_YELLOW)
    else
        midi_shift(COLOR_OFF)
    end

    if UI_ALT_PRESSED then
        midi_alt(COLOR_YELLOW)
    else
        midi_alt(COLOR_OFF)
    end
end

--------------------------------------------------------------------------------
-- Converts an RGB color value to HSV. Conversion formula
-- adapted from http://en.wikipedia.org/wiki/HSV_color_space.
-- @param rgb (table), the RGB representation
-- @return table, the HSV representation
function rgb_to_hsv(rgb)
    local r, g, b = rgb[1] / 255, rgb[2] / 255, rgb[3] / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s, v
    v = max

    local d = max - min
    if max == 0 then
        s = 0
    else
        s = d / max
    end

    if max == min then
        h = 0 -- achromatic
    else
        if max == r then
            h = (g - b) / d
            if g < b then
                h = h + 6
            end
        elseif max == g then
            h = (b - r) / d + 2
        elseif max == b then
            h = (r - g) / d + 4
        end
        h = h / 6
    end

    return { h, s, v }
end

--------------------------------------------------------------------------------
-- Converts an HSV color value to RGB. Conversion formula
-- adapted from http://en.wikipedia.org/wiki/HSV_color_space.
-- @param hsv (table), the HSV representation
-- @return table, the RGB representation
function hsv_to_rgb(hsv)

    local h, s, v = hsv[1], hsv[2], hsv[3]
    local r, g, b

    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);

    i = i % 6

    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    return {
        math.floor(r * 255),
        math.floor(g * 255),
        math.floor(b * 255)
    }

end

function debug_key_handler(dialog, key)
    if (key.name == "esc") then
        dialog:close()
    else
        return key
    end
end

function build_debug_interface()
    -- Init VB
    local VB = renoise.ViewBuilder()

    local top_row = VB:row { margin = 2, spacing = 2, }
    UI_MODE_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "MODE:" .. UI_MODE,
        pressed = ui_mode_press,
        released = ui_mode_release
    }
    UI_KNOB1_DEBUG = VB:button {
        width = 35,
        height = 35,
        pressed = ui_knob1_touch,
    }
    UI_KNOB2_DEBUG = VB:button {
        width = 35,
        height = 35,
        pressed = ui_knob2_touch,
    }
    UI_KNOB3_DEBUG = VB:button {
        width = 35,
        height = 35,
        pressed = ui_knob3_touch,
    }
    UI_KNOB4_DEBUG = VB:button {
        width = 35,
        height = 35,
        pressed = ui_knob4_touch,
    }
    UI_PATTERN_PREV_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "PAT-",
        pressed = ui_pattern_prev
    }
    UI_PATTERN_NEXT_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "PAT+",
        pressed = ui_pattern_next
    }
    local UI_SELECT_PREV_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "SEL-",
        pressed = ui_select_prev
    }
    local UI_SELECT_NEXT_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "SEL+",
        pressed = ui_select_next
    }
    UI_BROWSE_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "BROWSE",
        pressed = ui_browse_press
    }
    UI_GRID_PREV_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "GRID-",
        pressed = ui_grid_prev
    }
    UI_GRID_NEXT_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "GRID+",
        pressed = ui_grid_next
    }
    top_row:add_child(UI_MODE_DEBUG)
    top_row:add_child(UI_KNOB1_DEBUG)
    top_row:add_child(UI_KNOB2_DEBUG)
    top_row:add_child(UI_KNOB3_DEBUG)
    top_row:add_child(UI_KNOB4_DEBUG)
    top_row:add_child(UI_PATTERN_PREV_DEBUG)
    top_row:add_child(UI_PATTERN_NEXT_DEBUG)
    top_row:add_child(UI_SELECT_PREV_DEBUG)
    top_row:add_child(UI_SELECT_NEXT_DEBUG)
    top_row:add_child(UI_BROWSE_DEBUG)
    top_row:add_child(UI_GRID_PREV_DEBUG)
    top_row:add_child(UI_GRID_NEXT_DEBUG)

    -- Checkmark Matrix
    local columns = VB:column { }
    columns:add_child(top_row)

    for r = 1, PAD_ROWS do
        local row = VB:row { margin = 2, spacing = 2, }
        ROW_SELECT_DEBUG[r] = VB:button {
            width = 35,
            height = 35,
            pressed = function()
                ui_row_select(r)
            end
        }
        row:add_child(ROW_SELECT_DEBUG[r])

        ROW_INDICATOR_DEBUG[r] = VB:button {
            width = 17,
            height = 35
        }
        row:add_child(ROW_INDICATOR_DEBUG[r])

        PADS_DEBUG[r] = table.create()
        for c = 1, PAD_COLUMNS do
            PADS_DEBUG[r][c] = VB:button {
                width = 35,
                height = 35,
                pressed = function()
                    ui_pad_press(r, c)
                end,
                released = function()
                    ui_pad_release(r, c)
                end
                --          midi_mapping = "Grid Pie:Slice " .. x .. "," .. y,
            }
            row:add_child(PADS_DEBUG[r][c])
        end
        columns:add_child(row)
    end

    local lower_row = VB:row { margin = 2, spacing = 2, }
    UI_STEP_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "STEP",
        pressed = function()
            if UI_STEP_PRESSED then
                ui_step_release()
            else
                ui_step_press()
            end
        end
    }
    UI_NOTE_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "NOTE",
        pressed = ui_note_press
    }
    UI_DRUM_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "DRUM",
        pressed = ui_drum_press
    }
    UI_PERFORM_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "PERFORM",
        pressed = ui_perform_press
    }
    UI_SHIFT_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "SHIFT",
        pressed = function()
            if UI_SHIFT_PRESSED then
                ui_shift_release()
            else
                ui_shift_press()
            end
        end
    }
    UI_ALT_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "ALT",
        pressed = function()
            if UI_ALT_PRESSED then
                ui_alt_release()
            else
                ui_alt_press()
            end
        end
    }
    UI_SONG_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "SONG",
        pressed = ui_song_press
    }
    UI_PLAY_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "PLAY",
        pressed = ui_play_press
    }
    UI_STOP_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "STOP",
        pressed = ui_stop_press
    }
    UI_REC_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "REC",
        pressed = ui_rec_press
    }

    lower_row:add_child(UI_STEP_DEBUG)
    lower_row:add_child(UI_NOTE_DEBUG)
    lower_row:add_child(UI_DRUM_DEBUG)
    lower_row:add_child(UI_PERFORM_DEBUG)
    lower_row:add_child(UI_SHIFT_DEBUG)
    lower_row:add_child(UI_ALT_DEBUG)
    lower_row:add_child(UI_SONG_DEBUG)
    lower_row:add_child(UI_PLAY_DEBUG)
    lower_row:add_child(UI_STOP_DEBUG)
    lower_row:add_child(UI_REC_DEBUG)

    columns:add_child(lower_row)

    -- Racks
    MY_INTERFACE_RACK = VB:column {
        uniform = true,
        margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
        spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,

        VB:column {
            VB:horizontal_aligner {
                mode = "center",
                columns,
            },
        },
    }
end

local MIDI_NOTE_ON_ACTIONS = {
    [0x10] = ui_knob1_touch,
    [0x11] = ui_knob2_touch,
    [0x12] = ui_knob3_touch,
    [0x13] = ui_knob4_touch,
    [0x19] = nil, -- SELECT
    [0x1a] = ui_mode_press,
    [0x1f] = ui_pattern_prev,
    [0x20] = ui_pattern_next,
    [0x21] = ui_browse_press,
    [0x22] = ui_grid_prev,
    [0x23] = ui_grid_next,
    [0x24] = function()
        ui_row_select(1)
    end,
    [0x25] = function()
        ui_row_select(2)
    end,
    [0x26] = function()
        ui_row_select(3)
    end,
    [0x27] = function()
        ui_row_select(4)
    end,
    [0x2c] = ui_step_press,
    [0x2d] = ui_note_press,
    [0x2e] = ui_drum_press,
    [0x2f] = ui_perform_press,
    [0x30] = ui_shift_press,
    [0x31] = ui_alt_press,
    [0x32] = ui_song_press,
    [0x33] = ui_play_press,
    [0x34] = ui_stop_press,
    [0x35] = ui_rec_press,
}

local MIDI_NOTE_OFF_ACTIONS = {
    [0x10] = nil, -- ui_knob1_touch
    [0x11] = nil, --ui_knob2_touch
    [0x12] = nil, -- ui_knob3_touch
    [0x13] = nil, -- ui_knob4_touch
    [0x19] = nil, -- SELECT
    [0x1a] = ui_mode_release,
    [0x1f] = nil, -- ui_pattern_prev
    [0x20] = nil, -- ui_pattern_next
    [0x21] = nil, -- ui_browse_press
    [0x22] = nil, -- ui_grid_prev
    [0x23] = nil, -- ui_grid_next
    [0x24] = nil, -- function() ui_row_select(1) end
    [0x25] = nil, -- function() ui_row_select(2) end
    [0x26] = nil, -- function() ui_row_select(3) end
    [0x27] = nil, -- function() ui_row_select(4) end
    [0x2c] = ui_step_release,
    [0x2d] = nil, -- ui_note_press
    [0x2e] = nil, -- ui_drum_press
    [0x2f] = nil, -- ui_perform_press
    [0x30] = ui_shift_release,
    [0x31] = ui_alt_release,
    [0x32] = nil, -- ui_song_press
    [0x33] = nil, -- ui_play_press
    [0x34] = nil, -- ui_stop_press
    [0x35] = nil, -- ui_rec_press
}

local MIDI_CC_ACTIONS = {
    [0x10] = ui_knob1,
    [0x11] = ui_knob2,
    [0x12] = ui_knob3,
    [0x13] = ui_knob4,
    [0x76] = ui_select
}

function get_color_index(color, red, yellow, green)
    if yellow and red then
        if color[1] == 0 and color[2] == 0 then
            return 0
        elseif color[1] < 128 and color[2] == 0 then
            return 1
        elseif color[1] < 256 and color[2] == 0 then
            return 3
        elseif color[1] < 128 and color[2] < 128 then
            return 2
        elseif color[1] < 256 and color[2] < 256 then
            return 4
        end
    elseif yellow and green then
        if color[2] == 0 and color[1] == 0 then
            return 0
        elseif color[2] < 128 and color[1] == 0 then
            return 1
        elseif color[2] < 256 and color[1] == 0 then
            return 3
        elseif color[2] < 128 and color[1] < 128 then
            return 2
        elseif color[2] < 256 and color[1] < 256 then
            return 4
        end
    elseif red and green then
        if color[1] == 0 and color[2] == 0 then
            return 0
        elseif color[1] < 128 and color[2] == 0 then
            return 1
        elseif color[2] < 128 and color[1] == 0 then
            return 2
        elseif color[1] < 256 and color[2] == 0 then
            return 3
        elseif color[2] < 256 and color[1] == 0 then
            return 4
        end

    elseif yellow then
        if color[1] == 0 and color[2] == 0 then
            return 0
        elseif color[1] < 128 and color[2] < 128 then
            return 1
        elseif color[1] < 256 and color[2] < 256 then
            return 2
        end
    elseif green then
        if color[2] == 0 then
            return 0
        elseif color[2] < 128 then
            return 1
        elseif color[2] < 256 then
            return 2
        end
    elseif red then
        if color[1] == 0 then
            return 0
        elseif color[1] < 128 then
            return 1
        elseif color[1] < 256 then
            return 2
        end
    end
    return 0
end

function midi_init()
    for i = 0, PAD_ROWS - 1 do
        for j = 0, PAD_COLUMNS - 1 do
            MIDI_NOTE_ON_ACTIONS[0x36 + i * 16 + j] = function()
                ui_pad_press(i + 1, j + 1)
            end
            MIDI_NOTE_OFF_ACTIONS[0x36 + i * 16 + j] = function()
                ui_pad_release(i + 1, j + 1)
            end
        end
    end

    if not (renoise.Midi.devices_changed_observable():has_notifier(midi_connect)) then
        renoise.Midi.devices_changed_observable():add_notifier(midi_connect)
    end
    midi_connect()
end

function midi_disconnect()
    if MIDI_IN ~= nil then
        MIDI_IN:close()
    end
    if MIDI_OUT ~= nil then
        MIDI_OUT:close()
    end

    MIDI_IN = nil
    MIDI_OUT = nil
end

function midi_connect()
    if MIDI_IN == nil
            and MIDI_OUT == nil
            and table.find(renoise.Midi.available_input_devices(), MIDI_IN_PORT) ~= nil
            and table.find(renoise.Midi.available_output_devices(), MIDI_OUT_PORT) ~= nil then
        MIDI_IN = renoise.Midi.create_input_device(MIDI_IN_PORT, midi_callback)
        MIDI_OUT = renoise.Midi.create_output_device(MIDI_OUT_PORT)

        midi_rec(COLOR_OFF)
        midi_play(COLOR_OFF)
        midi_stop(COLOR_OFF)
        midi_song(COLOR_OFF)
        midi_perform(COLOR_OFF)
        midi_drum(COLOR_OFF)
        midi_note(COLOR_OFF)
        midi_mode(0)
        midi_pattern_prev(COLOR_OFF)
        midi_pattern_next(COLOR_OFF)
        midi_grid_prev(COLOR_OFF)
        midi_grid_next(COLOR_OFF)
        midi_shift(COLOR_OFF)
        midi_alt(COLOR_OFF)
        midi_step(COLOR_OFF)

        local sysex = midi_pad_start()
        for i = 1, PAD_ROWS do
            midi_row(i, COLOR_OFF)
            midi_indicator(i, COLOR_OFF)
            for j = 1, PAD_COLUMNS do
                midi_pad(sysex, i, j, COLOR_OFF)
            end
        end
        midi_pad_end(sysex)

        for r = 1, PAD_ROWS do
            ROW_SELECT_2ND[r] = { -1, -1, -1 }
            ROW_INDICATOR_2ND[r] = { -1, -1, -1 }
            for c = 1, PAD_COLUMNS do
                PADS[r][c] = { 0, 0, 0, false }
                PADS_2ND[r][c] = { -1, -1, -1, false }
            end
        end

        render_debug()
        ui_update_nav_buttons()
        ui_update_state_buttons()
    else
        midi_disconnect()
        if OPTIONS.DevelopmentMode.value then
            renoise.tool():add_timer(show_dev_window, 1)
        else
            if MY_INTERFACE ~= nil then
                MY_INTERFACE:close()
                MY_INTERFACE = nil
            end
        end
    end
end

function show_dev_window()
    if MY_INTERFACE == nil or not MY_INTERFACE.visible then
        MY_INTERFACE = renoise.app():show_custom_dialog("FIRE", MY_INTERFACE_RACK, debug_key_handler)
    else
        MY_INTERFACE:show()
    end
    renoise.tool():remove_timer(show_dev_window)
end

function midi_mode(value)
    UI_MODE_DEBUG.text = 'MODE:' .. math.floor(value % 16)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x1b, 0x10 + math.floor(value % 16) }
end

function midi_pattern_prev(color)
    UI_PATTERN_PREV_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x1f, get_color_index(color, true, false, false) }
end

function midi_pattern_next(color)
    UI_PATTERN_NEXT_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x20, get_color_index(color, true, false, false) }
end

function midi_browse(color)
    UI_BROWSE_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x21, get_color_index(color, true, false, false) }
end

function midi_grid_prev(color)
    UI_GRID_PREV_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x22, get_color_index(color, true, false, false) }
end

function midi_grid_next(color)
    UI_GRID_NEXT_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x23, get_color_index(color, true, false, false) }
end

function midi_row(row, color)
    ROW_SELECT_DEBUG[row].color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x24 + row - 1, get_color_index(color, false, false, true) }
end

function midi_indicator(row, color)
    ROW_INDICATOR[row].color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x28 + row - 1, get_color_index(color, true, false, true) }
end

function midi_alt(color)
    UI_ALT_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x31, get_color_index(color, false, true, false) }
end

function midi_stop(color)
    UI_STOP_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x34, get_color_index(color, false, true, false) }
end

function midi_step(color)
    UI_STEP_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x2c, get_color_index(color, true, true, false) }
end

function midi_note(color)
    UI_NOTE_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x2d, get_color_index(color, true, true, false) }
end

function midi_drum(color)
    UI_DRUM_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x2e, get_color_index(color, true, true, false) }
end

function midi_perform(color)
    UI_PERFORM_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x2f, get_color_index(color, true, true, false) }
end

function midi_shift(color)
    UI_SHIFT_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x30, get_color_index(color, true, true, false) }
end

function midi_rec(color)
    UI_REC_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x35, get_color_index(color, true, true, false) }
end

function midi_song(color)
    UI_SONG_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x32, get_color_index(color, false, true, true) }
end

function midi_play(color)
    UI_PLAY_DEBUG.color = black(color)
    if MIDI_OUT == nil then
        return
    end
    MIDI_OUT:send { 0xb0, 0x33, get_color_index(color, false, true, true) }
end

function midi_pad_start()
    return { 0xf0, 0x47, 0x7f, 0x43, 0x65, 0x00, 0x00 }
end

function midi_pad(array, row, column, color)
    PADS_DEBUG[row][column].color = black(color)
    local pos = #array + 1
    array[pos] = (row - 1) * 16 + column - 1
    array[pos + 1] = bit.rshift(color[1], 1)
    array[pos + 2] = bit.rshift(color[2], 1)
    array[pos + 3] = bit.rshift(color[3], 1)
end

function midi_pad_end(array)
    if MIDI_OUT == nil then
        return
    end
    local payload_len = #array - 7
    if payload_len == 0 then
        return
    end
    array[6] = bit.rshift(payload_len, 7)
    array[7] = bit.band(payload_len, 0x7f)
    array[#array + 1] = 0xf7
    MIDI_OUT:send(array)
end

function midi_callback(message)
    if message[1] == 0x90 then
        local handler = MIDI_NOTE_ON_ACTIONS[message[2]]
        if handler ~= nil then
            handler()
        end
    elseif message[1] == 0x80 then
        local handler = MIDI_NOTE_OFF_ACTIONS[message[2]]
        if handler ~= nil then
            handler()
        end
    elseif message[1] == 0xb0 then
        local handler = MIDI_CC_ACTIONS[message[2]]
        local value = message[3]
        if value > 0x3f then
            value = value - 0x80
        end
        if handler ~= nil then
            handler(value)
        end
    end
end

function black(color)
    return {
        math.min(255, color[1]+1),
        math.min(255, color[2]+1),
        math.min(255, color[3]+1)
    }
end

function midi_configure()
    -- Init VB
    local VB = renoise.ViewBuilder()

    local midi_in_selected = MIDI_IN_PORT
    local midi_out_selected = MIDI_OUT_PORT

    local midi_in_text = VB:text {
        width = 100,
        text = "MIDI in [" .. midi_in_selected .. "]"
    }
    local midi_out_text = VB:text {
        width = 100,
        text = "MIDI out [" .. midi_out_selected .. "]"
    }

    local midi_in_ports = renoise.Midi.available_input_devices()
    local midi_out_ports = renoise.Midi.available_output_devices()
    table.insert(midi_in_ports, 1, "(default = FL STUDIO FIRE)")
    table.insert(midi_out_ports, 1, "(default = FL STUDIO FIRE)")

    local view = VB:column {
        uniform = true,
        margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
        spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,

        VB:column {
            midi_in_text,

            VB:popup {
                width = 300,
                value = table.find(midi_in_ports, midi_in_selected),
                items = midi_in_ports,
                notifier = function(new_index)
                    if new_index ~= nil and new_index > 1 then
                        midi_in_selected = midi_in_ports[new_index]
                    else
                        midi_in_selected = "FL STUDIO FIRE"
                    end
                    midi_in_text.text = "MIDI in [" .. midi_in_selected .. "]"
                end
            },

            midi_out_text,

            VB:popup {
                width = 300,
                value = table.find(midi_out_ports, midi_in_selected),
                items = midi_out_ports,
                notifier = function(new_index)
                    if new_index ~= nil and new_index > 1 then
                        midi_out_selected = midi_out_ports[new_index]
                    else
                        midi_out_selected = "FL STUDIO FIRE"
                    end
                    midi_out_text.text = "MIDI out [" .. midi_out_selected .. "]"
                end
            },

            VB:row {
                VB:checkbox {
                    value = OPTIONS.DevelopmentMode.value,
                    notifier = function(new_value)
                        OPTIONS.DevelopmentMode.value = new_value
                    end
                },
                VB:text {
                    text = "Show development view if no device is connected"
                }
            }
        },
    }

    if renoise.app():show_custom_prompt("Configure AKAI Fire Integration", view, { "Save", "Cancel" }) == "Save" then
        MIDI_IN_PORT = midi_in_selected
        MIDI_OUT_PORT = midi_out_selected
        OPTIONS.MidiInput.value = MIDI_IN_PORT
        OPTIONS.MidiOutput.value = MIDI_OUT_PORT
        midi_disconnect()
        midi_connect()
    end
end

--------------------------------------------------------------------------------
--  Menu
--------------------------------------------------------------------------------

renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:Configure AKAI Fire Integration...",
    invoke = function()
        midi_configure()
    end
}


initialize(true) 

