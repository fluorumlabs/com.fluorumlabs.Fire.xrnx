-- set up include-path
_clibroot = 'cLib/classes/'
_xlibroot = 'xLib/classes/'

_trace_filters = nil

-- require some classes
require (_clibroot..'cDebug')
require (_xlibroot..'xLib')
require (_xlibroot..'xPatternSequencer')

rns = nil

local MIDI_IN
local MIDI_OUT

local PAD_ROWS = 4
local PAD_COLUMNS = 16
local PADS = table.create()
local PADS_2ND = table.create()
local ROW_SELECT = table.create()
local ROW_SELECT_2ND = table.create()
local ROW_INDICATOR = table.create()
local ROW_INDICATOR_2ND = table.create()

local FLAT_ROWS = table.create()

local PADS_DEBUG = table.create()
local ROW_SELECT_DEBUG = table.create()
local ROW_INDICATOR_DEBUG = table.create()

local MODE_NOTE = 1
local MODE_DRUM = 2
local MODE_PERFORM = 3
local MODE_PERFORM_ALT = 4

local MODE = MODE_NOTE

local NOTE_STEP_VIEW_POS = 1
local NOTE_COLUMN_VIEW_POS = 1
local NOTE_CURSOR_POS = 1

local PERFORM_TRACK_VIEW_POS = 1
local PERFORM_SEQUENCE_VIEW_POS = 1

local CURRENT_PATTERN = nil
local CURRENT_LINE = -1
local CURRENT_SEQUENCE = -1
local CURRENT_TRACK = -1
local CURRENT_NOTE_COLUMN = -1
local PLAYBACK_LINE = -1
local PLAYBACK_BEAT = -1
local PLAYBACK_SEQUENCE = -1
local PLAYBACK_NEXT_SEQUENCE = -1

local CURRENT_ROW = 1

local UI_MODE = 1
local UI_MODE_PRESSED = false
local UI_MODE_DEBUG

local UI_KNOB1_DEBUG
local UI_KNOB2_DEBUG
local UI_KNOB3_DEBUG
local UI_KNOB4_DEBUG

local UI_PAD_PRESSED_COUNT = 0

local UI_SELECT_PRESSED = false

local UI_BROWSE_PRESSED = false
local UI_BROWSE_DEBUG

local UI_PATTERN_PREV_DEBUG
local UI_PATTERN_NEXT_DEBUG
local UI_GRID_PREV_DEBUG
local UI_GRID_NEXT_DEBUG

local UI_STEP_PRESSED = false
local UI_STEP_PROCESSED = false
local UI_STEP_DEBUG
local UI_NOTE_PRESSED = false
local UI_NOTE_DEBUG
local UI_DRUM_PRESSED = false
local UI_DRUM_DEBUG
local UI_PERFORM_PRESSED = false
local UI_PERFORM_DEBUG
local UI_SHIFT_PRESSED = false
local UI_SHIFT_DEBUG
local UI_ALT_PRESSED = false
local UI_ALT_DEBUG
local UI_SONG_PRESSED = false
local UI_SONG_DEBUG
local UI_PLAY_PRESSED = false
local UI_PLAY_DEBUG
local UI_STOP_PRESSED = false
local UI_STOP_DEBUG
local UI_REC_PRESSED = false
local UI_REC_DEBUG

local QUEUE_RENDER = false

local COLOR_OFF = {0,0,0}
local COLOR_RED_LOW = {127,0,0}
local COLOR_RED = {255,0,0}
local COLOR_GREEN_LOW = {0,127,0}
local COLOR_GREEN = {0,255,0}
local COLOR_YELLOW_LOW = {127,127,0}
local COLOR_YELLOW = {255,255,0}

function initialize() 
    build_debug_interface()

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

    renoise.tool().app_new_document_observable:add_notifier(function()
        rns = renoise.song()
    end)
    rns = renoise.song()

    midi_init()

    attach_notifier(nil)
    
    if not ( renoise.song().selected_pattern_observable:has_notifier(attach_notifier) ) then
        renoise.song().selected_pattern_observable:add_notifier(attach_notifier)
    end
    if not (renoise.tool().app_idle_observable:has_notifier(idler)) then
        renoise.tool().app_idle_observable:add_notifier(idler)
    end
    if not (renoise.song().tracks_observable:has_notifier(mark_as_dirty)) then
        renoise.song().tracks_observable:add_notifier(mark_as_dirty)
    end
    if not (renoise.song().sequencer.pattern_sequence_observable:has_notifier(mark_as_dirty)) then
        renoise.song().sequencer.pattern_sequence_observable:add_notifier(mark_as_dirty)
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
    ui_update_nav_buttons()
end

function attach_notifier(notification)
    if CURRENT_PATTERN ~= nil then
        CURRENT_PATTERN:remove_line_notifier(mark_as_dirty)
    end
    CURRENT_PATTERN = renoise.song().selected_pattern
    if not (CURRENT_PATTERN:has_line_notifier(mark_as_dirty)) then
        CURRENT_PATTERN:add_line_notifier(mark_as_dirty)
    end
    mark_as_dirty()
    ui_update_nav_buttons()
end

function mark_as_dirty(pos)
    QUEUE_RENDER = true
end

function idler(notification)
    local new_line_index = renoise.song().selected_line_index
    local new_sequence_index = renoise.song().selected_sequence_index
    local new_track_index = renoise.song().selected_track_index
    local new_note_column_index = renoise.song().selected_note_column_index
    local new_playback_line = renoise.song().transport.playback_pos.line
    local new_playback_sequence = renoise.song().transport.playback_pos.sequence
    local new_playback_beat = renoise.song().transport.playback_pos_beats
    if CURRENT_TRACK ~= new_track_index and new_note_column_index > 0 then
        CURRENT_TRACK = new_track_index
        QUEUE_RENDER = true
    end
    if CURRENT_LINE ~= new_line_index then
        CURRENT_LINE = new_line_index
        focus_line()
        QUEUE_RENDER = true
    end
    if CURRENT_SEQUENCE ~= new_sequence_index then
        CURRENT_SEQUENCE = new_sequence_index
        QUEUE_RENDER = true
    end
    if CURRENT_NOTE_COLUMN ~= new_note_column_index and new_note_column_index > 0 then
        CURRENT_NOTE_COLUMN = new_note_column_index
        QUEUE_RENDER = true
    end

    if UI_MODE ~= PLAYBACK_BEAT then
        UI_MODE = PLAYBACK_BEAT
        midi_mode(UI_MODE, true)
        UI_MODE_DEBUG.text = 'MODE:'..math.floor(UI_MODE % 16)
    end

    if QUEUE_RENDER then
        QUEUE_RENDER = false
        render()
        render_debug()
    elseif PLAYBACK_LINE ~= new_playback_line or PLAYBACK_SEQUENCE ~= new_playback_sequence then
        PLAYBACK_LINE = new_playback_line
        PLAYBACK_SEQUENCE = new_playback_sequence
        PLAYBACK_BEAT = new_playback_beat
        if PLAYBACK_NEXT_SEQUENCE == PLAYBACK_SEQUENCE then
            PLAYBACK_NEXT_SEQUENCE = -1
        end
        if MODE == MODE_DRUM or MODE == MODE_NOTE then
            render_note_cursor(renoise.song())
        elseif MODE == MODE_PERFORM then
            render()
        end
        render_debug()
    end

end

function render()
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        flat_rows(renoise.song())
        render_note()
    elseif MODE == MODE_PERFORM then
        render_perform()
--    elseif MODE == MODE_DRUM then
--        render_drum()
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
            midi_indicator(r,ROW_INDICATOR_2ND[r])
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
                        hsv[3] = 0.1
                    end
                else
                    if hsv[4] then
                        hsv[3] = hsv[3]+0.1
                        hsv[3] = math.min(hsv[3], 1.0)
                    end
                end
                PADS_DEBUG[r][c].color = hsv_to_rgb(hsv)
                midi_pad(sysex, r, c, hsv_to_rgb(hsv))
            end
        end

        midi_pad_end(sysex)
    end
end

function focus_line()
    local new_note_step_view_pos = CURRENT_LINE - ((CURRENT_LINE-1) % PAD_COLUMNS)
    if new_note_step_view_pos ~= NOTE_STEP_VIEW_POS then
        NOTE_STEP_VIEW_POS = new_note_step_view_pos
        ui_update_nav_buttons()
    end
end

function render_perform()
    for i = PERFORM_SEQUENCE_VIEW_POS, PERFORM_SEQUENCE_VIEW_POS+PAD_ROWS-1 do
        if i == CURRENT_SEQUENCE then
            ROW_SELECT[i-PERFORM_SEQUENCE_VIEW_POS+1] = {0,255,0}
        else
            ROW_SELECT[i-PERFORM_SEQUENCE_VIEW_POS+1] = {0,0,0}
        end
        if i == PLAYBACK_SEQUENCE then
            ROW_INDICATOR[i-PERFORM_SEQUENCE_VIEW_POS+1] = {255,0,0}
        elseif i == PLAYBACK_NEXT_SEQUENCE then
            ROW_INDICATOR[i-PERFORM_SEQUENCE_VIEW_POS+1] = {0,255,0}
        else
            ROW_INDICATOR[i-PERFORM_SEQUENCE_VIEW_POS+1] = {0,0,0}
        end
        for j = PERFORM_TRACK_VIEW_POS, PERFORM_TRACK_VIEW_POS+PAD_COLUMNS-1 do
            if i >= 1 and i <= #renoise.song().sequencer.pattern_sequence and j >= 1 and j <= renoise.song().sequencer_track_count then
                local cell = renoise.song():pattern(renoise.song().sequencer:pattern(i)):track(j)
                --local is_alias = false
                --if cell.is_alias then
                --    is_alias = true
                --    cell = renoise.song():pattern(cell.alias_pattern_index):track(j)
                --end
                if cell.color ~= nil then
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1] = rgb_to_hsv(cell.color)
                else
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1] = rgb_to_hsv(renoise.song():track(j).color)
                end
                PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][2] = 1.0
                if cell.is_empty then
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][1] = 0
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][2] = 0
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][3] = 0
                elseif renoise.song().sequencer:track_sequence_slot_is_muted(j,i) then
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][3] = 0.05
                else
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][3] = 0.9
                    --if not is_alias then
                    --    PADS[i][j][3] = PADS[i][j][3] * 2
                    --end
                end
                if i == CURRENT_SEQUENCE and j == CURRENT_TRACK then
                    if PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][1] ~= 0 or PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][2] ~= 0 then
                        PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][2] = 0.5
                    end
                    PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][3] = PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1][3] + 0.05
                end
            else
                PADS[i-PERFORM_SEQUENCE_VIEW_POS+1][j-PERFORM_TRACK_VIEW_POS+1] = {0,0,0,false}
            end
        end 
    end
end

function render_note_cursor(rns)
    local rns = renoise.song()

    local rows = FLAT_ROWS
    local rows_count = #rows

    local track_index = CURRENT_TRACK
    local note_column_index = CURRENT_NOTE_COLUMN

    local current_row = 0
    for i = 1, rows_count do
        if rows[i].track_index == track_index and rows[i].note_column_index == note_column_index then
            current_row = i
            break
        end
    end

    if current_row > 0 then
        CURRENT_ROW = current_row
    end

    -- adjust view pos
    --if NOTE_COLUMN_VIEW_POS > CURRENT_ROW then
    --    NOTE_COLUMN_VIEW_POS = CURRENT_ROW
    --elseif NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 < CURRENT_ROW then
    --    NOTE_COLUMN_VIEW_POS = CURRENT_ROW - PAD_ROWS + 1
    --end

    local new_step_pos = PLAYBACK_LINE - NOTE_STEP_VIEW_POS + 1
    if renoise.song().selected_sequence_index ~= PLAYBACK_SEQUENCE or new_step_pos <= 0 or new_step_pos > PAD_COLUMNS then
        new_step_pos = 0
    end

    for i = 1, PAD_ROWS do
        if rows[NOTE_COLUMN_VIEW_POS + i - 1].track_index == CURRENT_TRACK then
            ROW_SELECT[i] = { 0, 255, 0 }
        else
            ROW_SELECT[i] = { 0, 0, 0 }
        end

        --local playback_pattern_index = renoise.song().sequencer:pattern(renoise.song().transport.playback_pos.sequence)
        --local playback_track = renoise.song():pattern(playback_pattern_index):track(rows[NOTE_COLUMN_VIEW_POS+i-1].track_index)
        --local is_alias = false
        --if playback_track.is_alias then
        --    is_alias = true
        --    playback_pattern_index = playback_track.alias_pattern_index
        --end

        ROW_INDICATOR[i] = { 0, 0, 0 }

        if NOTE_CURSOR_POS > 0 then
            PADS[i][NOTE_CURSOR_POS][4] = false
        end
        if new_step_pos > 0 then
            PADS[i][new_step_pos][4] = true
        end
    end

    NOTE_CURSOR_POS = new_step_pos

    return rows
end

function render_note()
    local rns = renoise.song()

    local rows = render_note_cursor(rns)
    local last_note = table.create()

    if MODE == MODE_NOTE or (MODE == MODE_DRUM and UI_STEP_PRESSED) then
        local prev_track = -1
        for i = 1, NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 do 
            if rows[i] ~= nil then
                if last_note[i] == nil then
                    last_note[i] = -1
                end
                if prev_track ~= rows[i].track_index then
                    prev_track = rows[i].track_index
                    for pos,line in rns.pattern_iterator:note_columns_in_pattern_track(rns.selected_pattern_index,prev_track,true) do 
                        if pos.line >= NOTE_STEP_VIEW_POS then 
                            break
                        end
                        local note_value = line.note_value
                        if note_value == 120 then 
                            last_note[i+pos.column-1] = -1
                        elseif note_value < 120 then
                            last_note[i+pos.column-1] = note_value % 12
                        end
                    end
                end
            end
        end
        for i = NOTE_COLUMN_VIEW_POS, NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 do 
            if rows[i] ~= nil then
                render_note_row(rns, i, rows[i], last_note[i])
            end
        end
    else
        for i = NOTE_COLUMN_VIEW_POS, NOTE_COLUMN_VIEW_POS + PAD_ROWS - 1 do 
            if rows[i] ~= nil then
                render_drum_row(rns, i, rows[i], last_note[i])
            end
        end
    end
end

function is_selected_column(track, column, selection)
    if selection == nil then
        return track == CURRENT_TRACK and column == CURRENT_NOTE_COLUMN
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

function render_note_row(rns, ix, row, last_note)
    local track_index = row.track_index
    local note_column_index = row.note_column_index
    local color = rgb_to_hsv(rns.tracks[track_index].color)
    local line_count = renoise.song().selected_pattern.number_of_lines
    local selection = rns.selection_in_pattern
    local is_selected = is_selected_column(track_index, note_column_index, selection)

    local track = rns.selected_pattern.tracks[track_index]

    for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do 
        local pad = PADS[ix-NOTE_COLUMN_VIEW_POS+1][i-NOTE_STEP_VIEW_POS+1]
        if i <= line_count and i > 0 then
            local line = track:line(i)
            local note_value = line.note_columns[note_column_index].note_value
            if note_value < 120 then
                last_note = note_value % 12
            elseif note_value == 120 then
                last_note = -1
            end
            if last_note < 0 then
                pad[1] = 0.0
                pad[2] = 0.0
                pad[3] = 0.0
                if is_selected and is_selected_line(i, selection) then
                    pad[3] = pad[3] + 0.05
                end
            else
                pad[1] = last_note/12.0
                pad[2] = 1.0
                if note_value < 120 then
                    pad[3] = 0.9
                else
                    pad[3] = 0.1
                end
                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.5
                    pad[3] = pad[3] + 0.05
                end
            end
        else
            pad[1] = 0.0
            pad[2] = 0.0
            pad[3] = 0.0
        end
    end
end

function render_drum_row(rns, ix, row)
    local track_index = row.track_index
    local note_column_index = row.note_column_index
    local color = rgb_to_hsv(rns.tracks[track_index].color)
    local line_count = renoise.song().selected_pattern.number_of_lines
    local selection = rns.selection_in_pattern
    local is_selected = is_selected_column(track_index, note_column_index, selection)

    local track = rns.selected_pattern.tracks[track_index]

    for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS + PAD_COLUMNS - 1 do 
        local pad = PADS[ix-NOTE_COLUMN_VIEW_POS+1][i-NOTE_STEP_VIEW_POS+1]
        if i <= line_count and i > 0 then
            local line = track:line(i)
            local note_value = line.note_columns[note_column_index].note_value
            local volume_value = line.note_columns[note_column_index].volume_value
            if note_value >= 120 then
                pad[1] = 0.0
                pad[2] = 0.0
                pad[3] = 0.0
                if is_selected and is_selected_line(i, selection) then
                    pad[3] = pad[3] + 0.05
                end
            else
                pad[1] = color[1]
                pad[2] = 1.0
                
                if note_value < 120 and volume_value >= 128 then
                    pad[3] = 0.9
                elseif note_value < 120 then
                    pad[3] = 0.1 + 0.8 * volume_value / 128
                end

                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.5
                    pad[3] = pad[3] + 0.05
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
    local selection = renoise.song().selection_in_pattern
    if selection == nil then
        selection = {}
        selection.start_track = renoise.song().selected_track_index
        selection.end_track = renoise.song().selected_track_index
        selection.start_line = renoise.song().selected_line_index
        selection.end_line = renoise.song().selected_line_index
        selection.start_column = renoise.song().selected_note_column_index
        selection.end_column = renoise.song().selected_note_column_index
    end
    return selection
end

function set_selection(new_selection) 
    local selection = new_selection

    renoise.song().selected_track_index = selection.start_track

    if not (selection.start_line == 1 and selection.end_line == renoise.song().selected_pattern.number_of_lines) then
        renoise.song().selected_note_column_index = selection.start_column
        renoise.song().selected_line_index = selection.start_line
    end

    if selection.start_track == selection.end_track and selection.start_column == selection.end_column and selection.start_line == selection.end_line then
        renoise.song().selection_in_pattern = {}
    else
        renoise.song().selection_in_pattern = selection
    end

    
end

function shift_selection(steps, preserve)
    local selection = get_selection()
    local line_count = renoise.song().selected_pattern.number_of_lines
    local step_remap = table.create()
    local row_remap = table.create()

    if selection.end_line - selection.start_line == line_count - 1 then
        -- full pattern selected
        if steps > 0 then
            -- rotate right
            for i = 1, line_count-steps do
                step_remap[i] = steps;
            end
            for i = line_count-steps+1, line_count do
                step_remap[i] = steps - line_count
            end
        else
            -- rotate left
            for i = 1, -steps do
                step_remap[i] = line_count + steps;
            end
            for i = -steps+1, line_count do
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
            for i = selection.end_line+1, selection.end_line+steps do
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
            for i = selection.start_line+steps, selection.start_line-1 do
                step_remap[i] = selection.end_line - selection.start_line + 1
            end
        end
        selection.start_line = selection.start_line + steps
        selection.end_line = selection.end_line + steps
    end

    remap_selection(step_remap, row_remap, false)
    set_selection(selection)
    mark_as_dirty()
end

function get_nearest_note()
    local track = renoise.song().selected_pattern.tracks[renoise.song().selected_track_index]
    local line_count = renoise.song().selected_pattern.number_of_lines
    local line_index = renoise.song().selected_line_index
    local note_column_index = renoise.song().selected_note_column_index
    for i = 1, line_count do
        if line_index - i < 1 and line_index + i > line_count then
            return nil
        end
        if line_index - i >= 1 then
            local note_column = track:line(line_index-i).note_columns[note_column_index]
            if note_column.note_value < 120 then
                return note_column
            end
        end
        if line_index + i <= line_count then
            local note_column = track:line(line_index+i).note_columns[note_column_index]
            if note_column.note_value < 120 then
                return note_column
            end
        end
    end
end

function remap_selection(step_remap, row_remap, ignore_selection)
    local seq_len = renoise.song().transport.song_length.sequence+1
    local current_seq_index = renoise.song().selected_sequence_index
    local pattern_copy_index = renoise.song().sequencer:insert_new_pattern_at(seq_len)
    local pattern_copy = renoise.song():pattern(pattern_copy_index)
    renoise.song().selected_sequence_index = current_seq_index
    pattern_copy:copy_from(renoise.song().selected_pattern)

    local line_count = renoise.song().selected_pattern.number_of_lines
    for i = 1, #FLAT_ROWS do 
        local row = FLAT_ROWS[i]
        if row ~= nil and (ignore_selection or is_selected_column(row.track_index, row.note_column_index, renoise.song().selection_in_pattern)) then
            local track_index = row.track_index
            local note_column_index = row.note_column_index
            local new_track_index = track_index
            local new_note_column_index = note_column_index
            if row_remap[i] ~= nil then
                new_track_index = FLAT_ROWS[i+row_remap[i]].track_index
                new_note_column_index = FLAT_ROWS[i+row_remap[i]].note_column_index
            end
            local track = pattern_copy.tracks[track_index]
            local new_track = renoise.song().selected_pattern:track(new_track_index)

            for j = 1, line_count do
                local new_step_pos = j
                if step_remap[j] ~= nil then
                    new_step_pos = new_step_pos + step_remap[j]
                    local line = track:line(j)
                    local new_line = new_track:line(new_step_pos)
                    local data = line.note_columns[note_column_index]
                    local new_data = new_line.note_columns[new_note_column_index]
                    new_data:clear()
                    new_data.note_value = data.note_value
                    new_data.instrument_value = data.instrument_value
                    new_data.volume_value = data.volume_value
                    new_data.panning_value = data.panning_value
                    new_data.delay_value = data.delay_value
                    new_data.effect_number_value = data.effect_number_value
                    new_data.effect_amount_value = data.effect_amount_value
                end
            end
        end
    end
    renoise.song().sequencer:delete_sequence_at(seq_len)
    mark_as_dirty()
end

function apply_to_selection(apply)
    local line_count = renoise.song().selected_pattern.number_of_lines
    local selection = renoise.song().selection_in_pattern
    for i = 1, #FLAT_ROWS do 
        local row = FLAT_ROWS[i]
        if row ~= nil then
            local track_index = row.track_index
            local note_column_index = row.note_column_index
            local is_selected = is_selected_column(track_index, note_column_index, selection)
            local track = renoise.song().selected_pattern.tracks[track_index]

            for j = 1, line_count do
                local line = track:line(j)
                local data = line.note_columns[note_column_index]
                if is_selected and is_selected_line(j, selection) then
                    apply(data)
                end
            end
        end
    end
    mark_as_dirty()
end

function flat_rows(rns)
    FLAT_ROWS = table.create()
    local ix = 1

    for i = 1, rns.sequencer_track_count do
        for j = 1, rns.tracks[i].visible_note_columns do
            FLAT_ROWS[ix] = {}
            FLAT_ROWS[ix].track_index = i
            FLAT_ROWS[ix].note_column_index = j
            ix = ix + 1
        end
    end

    return FLAT_ROWS
end

function ui_pad_press(row, column)
    if MODE == MODE_PERFORM then
        local rns = renoise.song()
        local seq_ix = PERFORM_SEQUENCE_VIEW_POS + row - 1
        local track_ix = PERFORM_TRACK_VIEW_POS + column - 1
        if seq_ix >= 1 and seq_ix <= #renoise.song().sequencer.pattern_sequence and track_ix >= 1 and track_ix <= renoise.song().sequencer_track_count then
            if (not UI_SHIFT_PRESSED and UI_ALT_PRESSED) or UI_PAD_PRESSED_COUNT>=1 then
                local source = renoise.song():pattern(renoise.song().sequencer:pattern(rns.selected_sequence_index)):track(rns.selected_track_index)
                local target = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix)):track(track_ix)
                target:copy_from(source)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
                local source = renoise.song():pattern(renoise.song().sequencer:pattern(rns.selected_sequence_index)):track(rns.selected_track_index)
                local target = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix)):track(track_ix)
                target:copy_from(source)
                source:clear()
                rns.selected_sequence_index = seq_ix
                rns.selected_track_index = track_ix
                mark_as_dirty()
            elseif UI_STEP_PRESSED then
                rns.sequencer:set_track_sequence_slot_is_muted(track_ix,seq_ix,not rns.sequencer:track_sequence_slot_is_muted(track_ix,seq_ix))
                mark_as_dirty()
            elseif not UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
                rns.selected_sequence_index = seq_ix
                rns.selected_track_index = track_ix
                mark_as_dirty()
            end
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local rns = renoise.song()
        local rows = FLAT_ROWS

        local row_ix = NOTE_COLUMN_VIEW_POS + row - 1
        local column_ix = NOTE_STEP_VIEW_POS + column - 1

        local row = rows[row_ix]

        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            local track = rns.selected_pattern.tracks[row.track_index]
            local line_count = rns.selected_pattern.number_of_lines
            if column_ix+1 <= line_count then
                local note_column = track:line(column_ix+1).note_columns[row.note_column_index]
                if note_column.note_value == 120 then
                    note_column.note_value = 121
                elseif note_column.note_value == 121 then
                    note_column.note_value = 120
                end
            end

            -- clean following OFFs
            for i = column_ix, 1, -1 do
                local note_column = track:line(i).note_columns[row.note_column_index]
                if note_column.note_value == 120 then
                    note_column.note_value = 121
                elseif note_column.note_value < 120 then
                    break
                end
            end
            if column_ix+1 <= line_count and track:line(column_ix+1).note_columns[row.note_column_index].note_value >= 120 then
                for i = column_ix+2, line_count do
                    local note_column = track:line(i).note_columns[row.note_column_index]
                    if note_column.note_value == 120 then
                        note_column.note_value = 121
                    elseif note_column.note_value < 120 then
                        break
                    end
                end
            end
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            if is_selected_column(row.track_index, row.note_column_index, renoise.song().selection_in_pattern) and is_selected_line(column_ix, renoise.song().selection_in_pattern) then
                local EMPTY_VOLUME = renoise.PatternLine.EMPTY_VOLUME
                local EMPTY_INSTRUMENT = renoise.PatternLine.EMPTY_INSTRUMENT

                apply_to_selection(function(note_column)
                    note_column:clear()
                end)
            end
        elseif UI_SHIFT_PRESSED or UI_PAD_PRESSED_COUNT >= 1 then
            local start_line = rns.selected_line_index
            local start_track = rns.selected_track_index
            local start_column = rns.selected_note_column_index
            local end_line = column_ix
            local end_track = row.track_index
            local end_column = row.note_column_index
        
            if start_line > end_line then
                start_line = column_ix
                end_line = rns.selected_line_index
            end
            if start_track > end_track then
                start_track = row.track_index
                start_column = row.note_column_index
                end_track = rns.selected_track_index
                end_column = rns.selected_note_column_index
            elseif start_track == end_track and start_column > end_column then
                start_column = row.note_column_index
                end_column = rns.selected_note_column_index
            end

            -- expand end column if needed
            if rns.tracks[end_track].visible_note_columns == end_column then
                end_column = end_column + rns.tracks[end_track].visible_effect_columns
            end
            
            renoise.song().selection_in_pattern = {
                start_line = start_line,
                start_column = start_column,
                start_track = start_track,
                end_line = end_line,
                end_column = end_column,
                end_track = end_track
            }
        elseif UI_ALT_PRESSED then
            local selected_row = nil
            local selection = get_selection()
            local row_remap = table.create()
            for i = 1, #FLAT_ROWS do
                if is_selected_column(FLAT_ROWS[i].track_index, FLAT_ROWS[i].note_column_index,selection) then
                    if selected_row == nil then
                        selected_row = i
                    end
                    if selected_row ~= nil then
                        if i + row_ix - selected_row < 1 or i + row_ix - selected_row > #FLAT_ROWS then
                            return
                        end
                        row_remap[i] = row_ix - selected_row
                    end
                end
            end
            local step_diff = column_ix - selection.start_line
            local step_remap = table.create()
            for i = selection.start_line, selection.end_line do
                step_remap[i] = step_diff
            end
            remap_selection(step_remap, row_remap, false)
            mark_as_dirty()
        else
            rns.selection_in_pattern = {}

            rns.selected_track_index = row.track_index
            rns.selected_note_column_index = row.note_column_index
            rns.selected_line_index = column_ix

            if MODE == MODE_DRUM then
                local track = rns.selected_pattern.tracks[rns.selected_track_index]
                local note_column = track:line(rns.selected_line_index).note_columns[rns.selected_note_column_index]
                if note_column.note_value < 120 then
                    note_column:clear()
                else
                    local nearest_note = get_nearest_note()
                    if nearest_note ~= nil then
                        note_column:clear()
                        note_column.note_value = nearest_note.note_value
                        note_column.instrument_value = nearest_note.instrument_value
                    end
                end
            end
        end

        mark_as_dirty()
    end

    UI_PAD_PRESSED_COUNT = UI_PAD_PRESSED_COUNT + 1
end

function ui_pad_release(row, column)
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
        local line_count = renoise.song().selected_pattern.number_of_lines
        local new_line
        if UI_SHIFT_PRESSED then
            new_line = renoise.song().selected_line_index - renoise.song().transport.edit_step
        else
            new_line = renoise.song().selected_line_index + renoise.song().transport.edit_step
        end
        if new_line > line_count then
            new_line = new_line - line_count
        end
        if new_line < 1 then
            new_line = new_line + line_count
        end
        if new_line >= 1 and new_line <= line_count then
            renoise.song().selected_line_index = new_line
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
    renoise.app().window.disk_browser_is_visible = UI_BROWSE_PRESSED
    renoise.app().window.instrument_box_is_visible = true
    ui_update_state_buttons()
end

function ui_grid_next()
    local line_count = renoise.song().selected_pattern.number_of_lines
    local track_count = rns.sequencer_track_count
    if MODE == MODE_PERFORM then
        if PERFORM_TRACK_VIEW_POS + PAD_COLUMNS <= track_count then
            PERFORM_TRACK_VIEW_POS = PERFORM_TRACK_VIEW_POS + 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local is_not_last = NOTE_STEP_VIEW_POS + PAD_COLUMNS < renoise.song().selected_pattern.number_of_lines
        local selection = get_selection()
        local is_whole_track_selected = selection.start_line == 1 and selection.end_line == line_count
        if is_not_last and UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS + PAD_COLUMNS*2, line_count do
                step_remap[i] = -PAD_COLUMNS
            end
            if is_whole_track_selected then
                remap_selection(step_remap, table.create(), false)
                for i = 1, #FLAT_ROWS do
                    if is_selected_column(FLAT_ROWS[i].track_index, FLAT_ROWS[i].note_column_index, selection) then
                        for j = line_count - PAD_COLUMNS + 1, line_count do
                            renoise.song().selected_pattern:track(FLAT_ROWS[i].track_index):line(j):note_column(FLAT_ROWS[i].note_column_index):clear()
                        end
                    end
                end
            else
                remap_selection(step_remap, table.create(), true)
                for i = 1, #FLAT_ROWS do
                    for j = line_count - PAD_COLUMNS + 1, line_count do
                        renoise.song().selected_pattern:track(FLAT_ROWS[i].track_index):line(j):clear()
                    end
                end
                renoise.song().selected_pattern.number_of_lines = renoise.song().selected_pattern.number_of_lines - PAD_COLUMNS
            end
        elseif is_not_last and UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS+PAD_COLUMNS-1 do
                step_remap[i] = PAD_COLUMNS
            end
            for i = NOTE_STEP_VIEW_POS+PAD_COLUMNS, NOTE_STEP_VIEW_POS+PAD_COLUMNS*2-1 do
                step_remap[i] = -PAD_COLUMNS
            end
            remap_selection(step_remap, table.create(), not is_whole_track_selected)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS+PAD_COLUMNS-1 do
                step_remap[i] = PAD_COLUMNS
            end
            if not is_not_last then
                renoise.song().selected_pattern.number_of_lines = renoise.song().selected_pattern.number_of_lines + PAD_COLUMNS
            end
            remap_selection(step_remap, table.create(), not is_whole_track_selected)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        elseif is_not_last then
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS + PAD_COLUMNS
        end
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_grid_prev()
    local line_count = renoise.song().selected_pattern.number_of_lines
    if MODE == MODE_PERFORM then
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
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS+PAD_COLUMNS, line_count do
                step_remap[i] = -PAD_COLUMNS
            end
            if is_whole_track_selected then
                remap_selection(step_remap, table.create(), false)
                for i = 1, #FLAT_ROWS do
                    if is_selected_column(FLAT_ROWS[i].track_index, FLAT_ROWS[i].note_column_index, selection) then
                        for j = line_count - PAD_COLUMNS + 1, line_count do
                            renoise.song().selected_pattern:track(FLAT_ROWS[i].track_index):line(j):note_column(FLAT_ROWS[i].note_column_index):clear()
                        end
                    end
                end
            else
                remap_selection(step_remap, table.create(), true)
                for i = 1, #FLAT_ROWS do
                    for j = line_count - PAD_COLUMNS + 1, line_count do
                        renoise.song().selected_pattern:track(FLAT_ROWS[i].track_index):line(j):clear()
                    end
                end
                renoise.song().selected_pattern.number_of_lines = renoise.song().selected_pattern.number_of_lines - PAD_COLUMNS
            end
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        elseif is_not_first and UI_SHIFT_PRESSED and not UI_ALT_PRESSED then
            local step_remap = table.create()
            for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS+PAD_COLUMNS-1 do
                step_remap[i] = -PAD_COLUMNS
            end
            for i = NOTE_STEP_VIEW_POS-PAD_COLUMNS, NOTE_STEP_VIEW_POS-1 do
                step_remap[i] = PAD_COLUMNS
            end
            remap_selection(step_remap, table.create(), not is_whole_track_selected)
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        elseif UI_ALT_PRESSED and not UI_SHIFT_PRESSED then
            if is_not_first then
                local step_remap = table.create()
                for i = NOTE_STEP_VIEW_POS, NOTE_STEP_VIEW_POS+PAD_COLUMNS-1 do
                    step_remap[i] = -PAD_COLUMNS
                end
                remap_selection(step_remap, table.create(), not is_whole_track_selected)
                NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
            else
                local step_remap = table.create()
                for i = NOTE_STEP_VIEW_POS, line_count do
                    step_remap[i] = PAD_COLUMNS
                end
                renoise.song().selected_pattern.number_of_lines = renoise.song().selected_pattern.number_of_lines + PAD_COLUMNS
                -- step 1: shift everything right
                remap_selection(step_remap, table.create(), true)
                if is_whole_track_selected then
                    -- step 2: clear unselected tracks                
                    for i = 1, #FLAT_ROWS do
                        if not is_selected_column(FLAT_ROWS[i].track_index, FLAT_ROWS[i].note_column_index, selection) then
                            for j = 1, PAD_COLUMNS do
                                renoise.song().selected_pattern:track(FLAT_ROWS[i].track_index):line(j):note_column(FLAT_ROWS[i].note_column_index):clear()
                            end
                        end
                    end
                end
            end
        elseif is_not_first then
            NOTE_STEP_VIEW_POS = NOTE_STEP_VIEW_POS - PAD_COLUMNS
        end
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_pattern_next()
    local seq_len = renoise.song().transport.song_length.sequence
    if MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS + 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_SHIFT_PRESSED then
            local seq_pos = renoise.song().selected_sequence_index
            if seq_pos < seq_len then
                renoise.song().selected_sequence_index = seq_pos+1
                ui_update_nav_buttons()
            end
        else
            if NOTE_COLUMN_VIEW_POS < #FLAT_ROWS - PAD_ROWS + 1 then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS + 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_pattern_prev()
    if MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS > 1 then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS - 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_SHIFT_PRESSED then
            local seq_pos = renoise.song().selected_sequence_index
            local seq_len = renoise.song().transport.song_length.sequence
            if seq_pos > 1 then
                renoise.song().selected_sequence_index = seq_pos-1
                ui_update_nav_buttons()
            end
        else
            if NOTE_COLUMN_VIEW_POS > 1 then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS - 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_select_prev()
    if UI_BROWSE_PRESSED then
        if rns.selected_instrument_index > 1 then
            rns.selected_instrument_index = rns.selected_instrument_index - 1
        end
    elseif MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS > 1 then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS - 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            if renoise.song().transport.edit_step > 0 then
                renoise.song().transport.edit_step = renoise.song().transport.edit_step-1
            end
        elseif UI_ALT_PRESSED then
            apply_to_selection(function(column) 
                if column.note_value > 12 and column.note_value < 120 then 
                    column.note_value = column.note_value - 12
                end
            end)
        elseif UI_SHIFT_PRESSED then
            shift_selection(-1,1)
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
    local seq_len = renoise.song().transport.song_length.sequence
    if UI_BROWSE_PRESSED then
        if rns.selected_instrument_index < #rns.instruments then
            rns.selected_instrument_index = rns.selected_instrument_index + 1
        end
    elseif MODE == MODE_PERFORM then
        if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
            PERFORM_SEQUENCE_VIEW_POS = PERFORM_SEQUENCE_VIEW_POS + 1
            ui_update_nav_buttons()
            mark_as_dirty()
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if UI_STEP_PRESSED then
            UI_STEP_PROCESSED = true
            if renoise.song().transport.edit_step < 64 then
                renoise.song().transport.edit_step = renoise.song().transport.edit_step+1
            end
        elseif UI_ALT_PRESSED then
            apply_to_selection(function(column) 
                if column.note_value < 120-12 then 
                    column.note_value = column.note_value + 12
                end
            end)
        elseif UI_SHIFT_PRESSED then
            shift_selection(1,1)
        else
            apply_to_selection(function(column) 
                if column.note_value < 120-1 then 
                    column.note_value = column.note_value + 1
                end
            end)
        end
    end
end

function ui_row_select(index)
    if MODE == MODE_PERFORM then
        local seq_ix = PERFORM_SEQUENCE_VIEW_POS + index - 1
        if seq_ix >= 1 and seq_ix <= #renoise.song().sequencer.pattern_sequence then
            if not UI_SHIFT_PRESSED and not UI_ALT_PRESSED and not UI_STEP_PRESSED then
                renoise.song().transport:set_scheduled_sequence(seq_ix)
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
                renoise.song().sequencer:insert_new_pattern_at(seq_ix+1)
                mark_as_dirty()
            elseif not UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
                if seq_ix < PLAYBACK_NEXT_SEQUENCE then 
                    PLAYBACK_NEXT_SEQUENCE = PLAYBACK_NEXT_SEQUENCE + 1
                end
                local source = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix))
                renoise.song().sequencer:insert_new_pattern_at(seq_ix+1)
                local target = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix+1))
                target:copy_from(source)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
                if seq_ix == PLAYBACK_NEXT_SEQUENCE then 
                    PLAYBACK_NEXT_SEQUENCE = -1
                elseif seq_ix < PLAYBACK_NEXT_SEQUENCE then
                    PLAYBACK_NEXT_SEQUENCE = PLAYBACK_NEXT_SEQUENCE - 1
                end
                if #renoise.song().sequencer.pattern_sequence > 1 then
                    renoise.song().sequencer:delete_sequence_at(seq_ix)
                    mark_as_dirty()
                end
            end
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        local row = FLAT_ROWS[NOTE_COLUMN_VIEW_POS + index - 1]

        if UI_STEP_PRESSED then
            local playback_pattern_index = renoise.song().sequencer:pattern(renoise.song().transport.playback_pos.sequence)
            local playback_track = renoise.song():pattern(playback_pattern_index):track(row.track_index)
            --local is_alias = false
            --if playback_track.is_alias then
            --    is_alias = true
            --    playback_pattern_index = playback_track.alias_pattern_index
            --end
    
            if playback_pattern_index == renoise.song().selected_pattern_index then
                if renoise.song().sequencer:track_sequence_slot_is_muted(row.track_index,renoise.song().selected_sequence_index) then
                    renoise.song().sequencer:set_track_sequence_slot_is_muted(row.track_index,renoise.song().selected_sequence_index,false)
                else
                    renoise.song().sequencer:set_track_sequence_slot_is_muted(row.track_index,renoise.song().selected_sequence_index,true)
                end
            end
        else
            local start_line = 1
            local start_track = row.track_index
            local start_column = row.note_column_index
            local end_line = renoise.song().selected_pattern.number_of_lines
            local end_track = row.track_index
            local end_column = row.note_column_index
            local selection = renoise.song().selection_in_pattern

            -- expand end column if needed
            --if renoise.song().tracks[end_track].visible_note_columns == end_column then
            --    end_column = end_column + renoise.song().tracks[end_track].visible_effect_columns
            --end

            if selection ~= nil then
                if selection.start_line == start_line and selection.end_line == end_line and is_selected_column(start_track, start_column, selection) then
                    if selection.start_column == 1 and selection.end_column >= renoise.song().tracks[end_track].visible_note_columns then
                        renoise.song().selection_in_pattern = {}
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
        end
    end
    mark_as_dirty()
end

function ui_note_press()
    if UI_SHIFT_PRESSED then
        rns.transport.record_quantize_enabled = not rns.transport.record_quantize_enabled
    else
        MODE = MODE_NOTE
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_drum_press()
    if UI_SHIFT_PRESSED then
        rns.transport.loop_block_enabled = not rns.transport.loop_block_enabled
    else
        MODE = MODE_DRUM
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_perform_press()
    if UI_SHIFT_PRESSED then
        renoise.app().window.upper_frame_is_visible = not renoise.app().window.upper_frame_is_visible
        if renoise.app().window.upper_frame_is_visible then
            renoise.app().window.active_upper_frame = renoise.ApplicationWindow.UPPER_FRAME_MASTER_SPECTRUM
        end
    else
        MODE = MODE_PERFORM
        renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
        ui_update_nav_buttons()
        mark_as_dirty()
    end
end

function ui_song_press()
    if UI_SHIFT_PRESSED then
        rns.transport.metronome_enabled = not rns.transport.metronome_enabled
    else
        rns.transport.loop_pattern = not rns.transport.loop_pattern
    end
end

function ui_play_press()
    if UI_SHIFT_PRESSED then
        rns.transport:start(renoise.Transport.PLAYMODE_RESTART_PATTERN)
    else
        rns.transport:start(renoise.Transport.PLAYMODE_CONTINUE_PATTERN)
    end
end

function ui_stop_press()
    if UI_SHIFT_PRESSED then
        rns.transport.metronome_precount_enabled = not rns.transport.metronome_precount_enabled
    else
        rns.transport:stop()
    end
end

function ui_rec_press()
    if UI_SHIFT_PRESSED then
        rns.transport.follow_player = not rns.transport.follow_player
    else
        rns.transport.edit_mode = not rns.transport.edit_mode
    end
end

function interpolate(volume, panning)
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        local line_count = renoise.song().selected_pattern.number_of_lines
        local selection = renoise.song().selection_in_pattern
        for i = 1, #FLAT_ROWS do 
            local row = FLAT_ROWS[i]
            if row ~= nil then
                local track_index = row.track_index
                local note_column_index = row.note_column_index
                local is_selected = is_selected_column(track_index, note_column_index, selection)
                local track = renoise.song().selected_pattern.tracks[track_index]
    
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
                    local data = line.note_columns[note_column_index]
                    if is_selected and is_selected_line(j, selection) then
                        if int_volume then
                            data.volume_value = start_volume + (end_volume-start_volume)/len*(j-start_line)
                        end
                        if int_panning then
                            data.panning_value = start_panning + (end_panning-start_panning)/len*(j-start_line)
                        end
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
            interpolate(true,false)
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data) data.volume_string = '..' end)
        end
    end
end

function ui_knob2_touch()
    if MODE == MODE_DRUM or MODE == MODE_NOTE then
        if UI_MODE_PRESSED then
            interpolate(false,true)
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data) data.panning_string = '..' end)
        end
    end
end

function ui_knob3_touch()
    if MODE == MODE_DRUM or MODE == MODE_NOTE then
        if UI_MODE_PRESSED then
        elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED then
            apply_to_selection(function(data) data.delay_string = '..' end)
        end
    end
end

function ui_knob4_touch()
    -- noop
end

function ui_knob1(value)
end

function ui_knob2(value)
end

function ui_knob3(value)
end

function ui_knob4(value)
end

function ui_select(value)
    if value > 0 then
        ui_select_next()
    else
        ui_select_prev()
    end
end

function ui_update_nav_buttons()
    local seq_pos = renoise.song().selected_sequence_index
    local seq_len = renoise.song().transport.song_length.sequence

    -- grid prev/next
    if MODE == MODE_NOTE then
        midi_note(COLOR_YELLOW)
        midi_drum(COLOR_OFF)
        midi_perform(COLOR_OFF)
        UI_NOTE_DEBUG.color = COLOR_YELLOW
        UI_DRUM_DEBUG.color = COLOR_OFF
        UI_PERFORM_DEBUG.color = COLOR_OFF
    elseif MODE == MODE_DRUM then
        midi_note(COLOR_OFF)
        midi_drum(COLOR_YELLOW)
        midi_perform(COLOR_OFF)
        UI_NOTE_DEBUG.color = COLOR_OFF
        UI_DRUM_DEBUG.color = COLOR_YELLOW
        UI_PERFORM_DEBUG.color = COLOR_OFF
    elseif MODE == MODE_PERFORM then
        midi_note(COLOR_OFF)
        midi_drum(COLOR_OFF)
        midi_perform(COLOR_YELLOW)
        UI_NOTE_DEBUG.color = COLOR_OFF
        UI_DRUM_DEBUG.color = COLOR_OFF
        UI_PERFORM_DEBUG.color = COLOR_YELLOW
    end

    if MODE == MODE_PERFORM then
        if PERFORM_TRACK_VIEW_POS > 1 then
            midi_grid_prev(COLOR_RED)
            UI_GRID_PREV_DEBUG.color = COLOR_RED
        else
            midi_grid_prev(COLOR_OFF)
            UI_GRID_PREV_DEBUG.color = COLOR_OFF
        end
        if PERFORM_TRACK_VIEW_POS + PAD_COLUMNS <= rns.sequencer_track_count then
            midi_grid_next(COLOR_RED)
            UI_GRID_NEXT_DEBUG.color = COLOR_RED
        else
            midi_grid_next(COLOR_OFF)
            UI_GRID_NEXT_DEBUG.color = COLOR_OFF
        end
        if PERFORM_SEQUENCE_VIEW_POS > 1 then
            midi_pattern_prev(COLOR_RED)
            UI_PATTERN_PREV_DEBUG.color = COLOR_RED
        else
            midi_pattern_prev(COLOR_OFF)
            UI_PATTERN_PREV_DEBUG.color = COLOR_OFF
        end
        if PERFORM_SEQUENCE_VIEW_POS + PAD_ROWS <= seq_len then
            midi_pattern_next(COLOR_RED)
            UI_PATTERN_NEXT_DEBUG.color = COLOR_RED
        else
            midi_pattern_next(COLOR_OFF)
            UI_PATTERN_NEXT_DEBUG.color = COLOR_OFF
        end
    elseif MODE == MODE_NOTE or MODE == MODE_DRUM then
        if NOTE_STEP_VIEW_POS > 1 then
            midi_grid_prev(COLOR_RED)
            UI_GRID_PREV_DEBUG.color = COLOR_RED
        else
            midi_grid_prev(COLOR_OFF)
            UI_GRID_PREV_DEBUG.color = COLOR_OFF
        end

        if NOTE_STEP_VIEW_POS + PAD_COLUMNS <= renoise.song().selected_pattern.number_of_lines then
            midi_grid_next(COLOR_RED)
            UI_GRID_NEXT_DEBUG.color = COLOR_RED
        else
            midi_grid_next(COLOR_OFF)
            UI_GRID_NEXT_DEBUG.color = COLOR_OFF
        end

        if UI_SHIFT_PRESSED then
            if seq_pos > 1 then
                midi_pattern_prev(COLOR_RED)
                UI_PATTERN_PREV_DEBUG.color = COLOR_RED
            else
                midi_pattern_prev(COLOR_OFF)
                UI_PATTERN_PREV_DEBUG.color = COLOR_OFF
            end

            if seq_pos < seq_len then
                midi_pattern_next(COLOR_RED)
                UI_PATTERN_NEXT_DEBUG.color = COLOR_RED
            else
                midi_pattern_next(COLOR_OFF)
                UI_PATTERN_NEXT_DEBUG.color = COLOR_OFF
            end
        else
            if NOTE_COLUMN_VIEW_POS > 1 then
                midi_pattern_prev(COLOR_RED)
                UI_PATTERN_PREV_DEBUG.color = COLOR_RED
            else
                midi_pattern_prev(COLOR_OFF)
                UI_PATTERN_PREV_DEBUG.color = COLOR_OFF
            end

            if NOTE_COLUMN_VIEW_POS < #FLAT_ROWS - PAD_ROWS + 1 then
                midi_pattern_next(COLOR_RED)
                UI_PATTERN_NEXT_DEBUG.color = COLOR_RED
            else
                midi_pattern_next(COLOR_OFF)
                UI_PATTERN_NEXT_DEBUG.color = COLOR_OFF
            end
        end

--    elseif MODE == MODE_DRUM then
--        render_drum()
    end
end

function ui_update_transport_buttons()
    if rns.transport.loop_pattern then
        midi_song(COLOR_GREEN)
        UI_SONG_DEBUG.color = COLOR_GREEN
    else
        midi_song(COLOR_YELLOW)
        UI_SONG_DEBUG.color = COLOR_YELLOW
    end

    if rns.transport.playing then
        midi_play(COLOR_GREEN)
        midi_stop(COLOR_OFF)
        UI_PLAY_DEBUG.color = COLOR_GREEN
        UI_STOP_DEBUG.color = COLOR_OFF
    else
        midi_play(COLOR_OFF)
        midi_stop(COLOR_YELLOW)
        UI_PLAY_DEBUG.color = COLOR_OFF
        UI_STOP_DEBUG.color = COLOR_YELLOW
    end

    if rns.transport.edit_mode then
        midi_rec(COLOR_RED)
        UI_REC_DEBUG.color = COLOR_RED
    else
        midi_rec(COLOR_OFF)
        UI_REC_DEBUG.color = COLOR_OFF
    end

    mark_as_dirty()
end

function ui_update_state_buttons()
    if UI_BROWSE_PRESSED then
        midi_browse(COLOR_RED)
        UI_BROWSE_DEBUG.color = COLOR_RED
    else
        midi_browse(COLOR_OFF)
        UI_BROWSE_DEBUG.color = COLOR_OFF
    end

    if UI_STEP_PRESSED then
        midi_step(COLOR_YELLOW)
        UI_STEP_DEBUG.color = COLOR_YELLOW
    else
        midi_step(COLOR_OFF)
        UI_STEP_DEBUG.color = COLOR_OFF
    end

    if UI_SHIFT_PRESSED then
        midi_shift(COLOR_YELLOW)
        UI_SHIFT_DEBUG.color = COLOR_YELLOW
    else
        midi_shift(COLOR_OFF)
        UI_SHIFT_DEBUG.color = COLOR_OFF
    end

    if UI_ALT_PRESSED then
        midi_alt(COLOR_YELLOW)
        UI_ALT_DEBUG.color = COLOR_YELLOW
    else
        midi_alt(COLOR_OFF)
        UI_ALT_DEBUG.color = COLOR_OFF
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
    if max == 0 then s = 0 else s = d / max end
  
    if max == min then
          h = 0 -- achromatic
    else
        if max == r then
        h = (g - b) / d
        if g < b then h = h + 6 end
        elseif max == g then h = (b - r) / d + 2
        elseif max == b then h = (r - g) / d + 4
        end
        h = h / 6
    end
  
    return {h,s,v}
end
  
--------------------------------------------------------------------------------
-- Converts an HSV color value to RGB. Conversion formula
-- adapted from http://en.wikipedia.org/wiki/HSV_color_space.
-- @param hsv (table), the HSV representation
-- @return table, the RGB representation
function hsv_to_rgb(hsv)
  
    local h, s, v = hsv[1],hsv[2],hsv[3]
    local r, g, b
  
    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);
  
    i = i % 6
  
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
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
 
    local top_row = VB:row {  margin = 2, spacing = 2, }
    UI_MODE_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "MODE:"..UI_MODE,
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
      local row = VB:row {  margin = 2, spacing = 2, }
      ROW_SELECT_DEBUG[r] = VB:button {
          width = 35,
          height = 35,
          pressed = function() ui_row_select(r) end
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
          pressed = function() ui_pad_press(r,c) end,
          released = function() ui_pad_release(r,c) end
--          midi_mapping = "Grid Pie:Slice " .. x .. "," .. y,
        }
        row:add_child(PADS_DEBUG[r][c])
      end
      columns:add_child(row)
    end

    local lower_row = VB:row {  margin = 2, spacing = 2, }
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
    local rack = VB:column {
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
  
    -- Show dialog
    local MY_INTERFACE = renoise.app():show_custom_dialog("FIRE", rack, debug_key_handler)
  
  end

--------------------------------------------------------------------------------
--  Menu
--------------------------------------------------------------------------------

local entry = {}

entry.name = "Main Menu:Tools:FIRE..."
entry.invoke = function() initialize(true) end
renoise.tool():add_menu_entry(entry)

function midi_mode_led(beat)
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
    [0x24] = function() ui_row_select(1) end,
    [0x25] = function() ui_row_select(2) end,
    [0x26] = function() ui_row_select(3) end,
    [0x27] = function() ui_row_select(4) end,
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
    for i = 0, PAD_ROWS-1 do
        for j = 0, PAD_COLUMNS-1 do
            MIDI_NOTE_ON_ACTIONS[0x36 + i*16 + j] = function() ui_pad_press(i+1, j+1) end
            MIDI_NOTE_OFF_ACTIONS[0x36 + i*16 + j] = function() ui_pad_release(i+1, j+1) end
        end
    end

    MIDI_IN = renoise.Midi.create_input_device('FL STUDIO FIRE', midi_callback)
    MIDI_OUT = renoise.Midi.create_output_device('FL STUDIO FIRE')
end

function midi_mode(value, extended)
    if not extended then
        MIDI_OUT:send {0xb0, 0x1b, math.floor(value % 4)}
    else
        MIDI_OUT:send {0xb0, 0x1b, 0x10 + math.floor(value % 16)}
    end
end

function midi_pattern_prev(color)
    MIDI_OUT:send {0xb0, 0x1f, get_color_index(color, true, false, false)}
end

function midi_pattern_next(color)
    MIDI_OUT:send {0xb0, 0x20, get_color_index(color, true, false, false)}
end

function midi_browse(color)
    MIDI_OUT:send {0xb0, 0x21, get_color_index(color, true, false, false)}
end

function midi_grid_prev(color)
    MIDI_OUT:send {0xb0, 0x22, get_color_index(color, true, false, false)}
end

function midi_grid_next(color)
    MIDI_OUT:send {0xb0, 0x23, get_color_index(color, true, false, false)}
end

function midi_row(row, color)
    MIDI_OUT:send {0xb0, 0x24 + row - 1, get_color_index(color, false, false, true)}
end

function midi_indicator(row, color)
    MIDI_OUT:send {0xb0, 0x28 + row - 1, get_color_index(color, true, false, true)}
end

function midi_alt(color)
    MIDI_OUT:send {0xb0, 0x31, get_color_index(color,false,true,false)}
end

function midi_stop(color)
    MIDI_OUT:send {0xb0, 0x34, get_color_index(color,false,true,false)}
end

function midi_step(color)
    MIDI_OUT:send {0xb0, 0x2c, get_color_index(color,true,true,false)}
end

function midi_note(color)
    MIDI_OUT:send {0xb0, 0x2d, get_color_index(color,true,true,false)}
end

function midi_drum(color)
    MIDI_OUT:send {0xb0, 0x2e, get_color_index(color,true,true,false)}
end

function midi_perform(color)
    MIDI_OUT:send {0xb0, 0x2f, get_color_index(color,true,true,false)}
end

function midi_shift(color)
    MIDI_OUT:send {0xb0, 0x30, get_color_index(color,true,true,false)}
end

function midi_rec(color)
    MIDI_OUT:send {0xb0, 0x35, get_color_index(color,true,true,false)}
end

function midi_song(color)
    MIDI_OUT:send {0xb0, 0x32, get_color_index(color,false,true,true)}
end

function midi_play(color)
    MIDI_OUT:send {0xb0, 0x33, get_color_index(color,false,true,true)}
end

function midi_pad_start()
    return { 0xf0, 0x47, 0x7f, 0x43, 0x65, 0x00, 0x00 }
end

function midi_pad(array,row,column,color)
    local pos = #array+1
    array[pos] = (row-1)*16 + column - 1
    array[pos+1] = bit.rshift(color[1],1)
    array[pos+2] = bit.rshift(color[2],1)
    array[pos+3] = bit.rshift(color[3],1)
end

function midi_pad_end(array)
    local payload_len = #array - 7
    if payload_len == 0 then
        return
    end
    array[6] = bit.rshift(payload_len,7)
    array[7] = bit.band(payload_len,0x7f)
    array[#array+1] = 0xf7
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