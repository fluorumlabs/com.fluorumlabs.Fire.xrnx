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
local PLAYBACK_SEQUENCE = -1

local CURRENT_ROW = 1

local UI_MODE = 1
local UI_MODE_DEBUG

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
    if QUEUE_RENDER then
        PLAYBACK_LINE = new_playback_line
        PLAYBACK_SEQUENCE = new_playback_sequence
        QUEUE_RENDER = false
        render()
        render_debug()
    elseif PLAYBACK_LINE ~= new_playback_line or PLAYBACK_SEQUENCE ~= new_playback_sequence then
        PLAYBACK_LINE = new_playback_line
        PLAYBACK_SEQUENCE = new_playback_sequence
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
            ROW_SELECT_DEBUG[r].color = ROW_SELECT_2ND[r]
        end

        if ROW_INDICATOR[r][1] ~= ROW_INDICATOR_2ND[r][1] or ROW_INDICATOR[r][2] ~= ROW_INDICATOR_2ND[r][2] or ROW_INDICATOR[r][3] ~= ROW_INDICATOR_2ND[r][3] then
            ROW_INDICATOR_2ND[r] = table.copy(ROW_INDICATOR[r])
            ROW_INDICATOR_DEBUG[r].color = ROW_INDICATOR_2ND[r]
        end

        for c = 1, PAD_COLUMNS do
            if PADS[r][c][1] ~= PADS_2ND[r][c][1] or PADS[r][c][2] ~= PADS_2ND[r][c][2] or PADS[r][c][3] ~= PADS_2ND[r][c][3] or PADS[r][c][4] ~= PADS_2ND[r][c][4] then
                PADS_2ND[r][c] = table.copy(PADS[r][c])
                local hsv = table.copy(PADS[r][c])
                if hsv[2] == 0 and hsv[3] == 0 then
                    hsv[1] = 0
                    hsv[3] = 0.01
                    if hsv[4] then
                        hsv[3] = 0.1
                    end
                else
                    if hsv[4] then
                        hsv[3] = hsv[3]+0.2
                        hsv[3] = math.min(hsv[3], 1.0)
                    end
                end
                PADS_DEBUG[r][c].color = hsv_to_rgb(hsv)
            end
        end
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
        for j = PERFORM_TRACK_VIEW_POS, PERFORM_TRACK_VIEW_POS+PAD_COLUMNS-1 do
            if i >= 1 and i <= #renoise.song().sequencer.pattern_sequence and j >= 1 and j <= renoise.song().sequencer_track_count then
                local cell = renoise.song():pattern(renoise.song().sequencer:pattern(i)):track(j)
                --local is_alias = false
                --if cell.is_alias then
                --    is_alias = true
                --    cell = renoise.song():pattern(cell.alias_pattern_index):track(j)
                --end
                if cell.color ~= nil then
                    PADS[i][j] = rgb_to_hsv(cell.color)
                else
                    PADS[i][j] = rgb_to_hsv(renoise.song():track(j).color)
                end
                PADS[i][j][2] = 1.0
                if cell.is_empty then
                    PADS[i][j][1] = 0
                    PADS[i][j][2] = 0
                    PADS[i][j][3] = 0.01
                elseif renoise.song().sequencer:track_sequence_slot_is_muted(j,i) then
                    PADS[i][j][3] = 0.2
                else
                    PADS[i][j][3] = 0.8
                    --if not is_alias then
                    --    PADS[i][j][3] = PADS[i][j][3] * 2
                    --end
                end
                if i == CURRENT_SEQUENCE and j == CURRENT_TRACK then
                    if PADS[i][j][1] ~= 0 or PADS[i][j][2] ~= 0 then
                        PADS[i][j][2] = 0.5
                    end
                    PADS[i][j][3] = PADS[i][j][3] + 0.2
                end
                PADS[i][j][4] = i == PLAYBACK_SEQUENCE
            else
                PADS[i][j] = {0,0,0.01,false}
                PADS[i][j][4] = i == PLAYBACK_SEQUENCE
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

        local playback_pattern_index = renoise.song().sequencer:pattern(renoise.song().transport.playback_pos.sequence)
        local playback_track = renoise.song():pattern(playback_pattern_index):track(rows[NOTE_COLUMN_VIEW_POS+i-1].track_index)
        --local is_alias = false
        --if playback_track.is_alias then
        --    is_alias = true
        --    playback_pattern_index = playback_track.alias_pattern_index
        --end

        if playback_pattern_index == renoise.song().selected_pattern_index then
            if rns.sequencer:track_sequence_slot_is_muted(rows[NOTE_COLUMN_VIEW_POS+i-1].track_index,renoise.song().selected_sequence_index) then
                ROW_INDICATOR[i] = { 255, 0, 0 }
            else
                ROW_INDICATOR[i] = { 0, 255, 0 }
            end
        else
            ROW_INDICATOR[i] = { 0, 0, 0 }
        end

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
                    pad[3] = pad[3] + 0.3
                end
            else
                pad[1] = last_note/12.0
                pad[2] = 1.0
                if note_value < 120 then
                    pad[3] = 0.8
                else
                    pad[3] = 0.3
                end
                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.5
                    pad[3] = pad[3] + 0.2
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
                    pad[3] = pad[3] + 0.3
                end
            else
                pad[1] = color[1]
                pad[2] = 1.0
                
                if note_value < 120 and volume_value >= 128 then
                    pad[3] = 0.8
                elseif note_value < 120 then
                    pad[3] = 0.3 + 0.5 * volume_value / 128
                end

                if is_selected and is_selected_line(i, selection) then
                    pad[2] = 0.5
                    pad[3] = pad[3] + 0.2
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
        if seq_ix >= 1 and seq_ix <= #renoise.song().sequencer.pattern_sequence and track_ix >= 1 and track_ix < renoise.song().sequencer_track_count then
            if (not UI_SELECT_PRESSED and UI_ALT_PRESSED) or UI_PAD_PRESSED_COUNT>=1 then
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
        elseif UI_SHIFT_PRESSED or UI_PAD_PRESSED_COUNT > 1 then
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
    if not UI_STEP_PROCESSED and (UI_MODE == MODE_NOTE or MODE == MODE_DRUM) then
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

function ui_grid_next()
    local line_count = renoise.song().selected_pattern.number_of_lines
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
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
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
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
    if UI_SHIFT_PRESSED then
        local seq_pos = renoise.song().selected_sequence_index
        local seq_len = renoise.song().transport.song_length.sequence
        if seq_pos < seq_len then
            renoise.song().selected_sequence_index = seq_pos+1
            ui_update_nav_buttons()
        end
    else
        if MODE == MODE_NOTE or MODE == MODE_DRUM then
            if NOTE_COLUMN_VIEW_POS < #FLAT_ROWS - PAD_ROWS + 1 then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS + 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_pattern_prev()
    if UI_SHIFT_PRESSED then
        local seq_pos = renoise.song().selected_sequence_index
        local seq_len = renoise.song().transport.song_length.sequence
        if seq_pos > 1 then
            renoise.song().selected_sequence_index = seq_pos-1
            ui_update_nav_buttons()
        end
    else
        if MODE == MODE_NOTE or MODE == MODE_DRUM then
            if NOTE_COLUMN_VIEW_POS > 1 then
                NOTE_COLUMN_VIEW_POS = NOTE_COLUMN_VIEW_POS - 1
                ui_update_nav_buttons()
                mark_as_dirty()
            end
        end
    end
end

function ui_select_prev()
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
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
    if MODE == MODE_NOTE or MODE == MODE_DRUM then
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
                mark_as_dirty()
            elseif not UI_SHIFT_PRESSED and not UI_ALT_PRESSED and UI_STEP_PRESSED then
                renoise.song().transport.playback_pos.sequence = seq_ix
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and not UI_ALT_PRESSED and not UI_STEP_PRESSED then
                renoise.song().sequencer:insert_new_pattern_at(seq_ix+1)
                mark_as_dirty()
            elseif not UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
                local source = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix))
                renoise.song().sequencer:insert_new_pattern_at(seq_ix+1)
                local target = renoise.song():pattern(renoise.song().sequencer:pattern(seq_ix+1))
                target:copy_from(source)
                mark_as_dirty()
            elseif UI_SHIFT_PRESSED and UI_ALT_PRESSED and not UI_STEP_PRESSED then
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
    MODE = MODE_NOTE
    ui_update_nav_buttons()
    mark_as_dirty()
end

function ui_drum_press()
    MODE = MODE_DRUM
    ui_update_nav_buttons()
    mark_as_dirty()
end

function ui_perform_press()
    MODE = MODE_PERFORM
    ui_update_nav_buttons()
    mark_as_dirty()
end

function ui_update_nav_buttons()
    local seq_pos = renoise.song().selected_sequence_index
    local seq_len = renoise.song().transport.song_length.sequence

    -- grid prev/next
    if MODE == MODE_NOTE then
        UI_NOTE_DEBUG.color = {255, 255, 0}
        UI_DRUM_DEBUG.color = {0,0,0}
        UI_PERFORM_DEBUG.color = {0,0,0}
    elseif MODE == MODE_DRUM then
        UI_NOTE_DEBUG.color = {0, 0, 0}
        UI_DRUM_DEBUG.color = {255,255,0}
        UI_PERFORM_DEBUG.color = {0,0,0}
    elseif MODE == MODE_PERFORM then
        UI_NOTE_DEBUG.color = {0, 0, 0}
        UI_DRUM_DEBUG.color = {0,0,0}
        UI_PERFORM_DEBUG.color = {255,255,0}
    end

    if MODE == MODE_NOTE or MODE == MODE_DRUM then
        if NOTE_STEP_VIEW_POS > 1 then
            UI_GRID_PREV_DEBUG.color = {255, 0, 0}
        else
            UI_GRID_PREV_DEBUG.color = {0, 0, 0}
        end

        if NOTE_STEP_VIEW_POS + PAD_COLUMNS < renoise.song().selected_pattern.number_of_lines then
            UI_GRID_NEXT_DEBUG.color = {255, 0, 0}
        else
            UI_GRID_NEXT_DEBUG.color = {0, 0, 0}
        end

        if UI_SHIFT_PRESSED then
            if seq_pos > 1 then
                UI_PATTERN_PREV_DEBUG.color = {255, 0, 0}
            else
                UI_PATTERN_PREV_DEBUG.color = {0, 0, 0}
            end

            if seq_pos < seq_len then
                UI_PATTERN_NEXT_DEBUG.color = {255, 0, 0}
            else
                UI_PATTERN_NEXT_DEBUG.color = {0, 0, 0}
            end
        else
            if NOTE_COLUMN_VIEW_POS > 1 then
                UI_PATTERN_PREV_DEBUG.color = {255, 0, 0}
            else
                UI_PATTERN_PREV_DEBUG.color = {0, 0, 0}
            end

            if NOTE_COLUMN_VIEW_POS < #FLAT_ROWS - PAD_ROWS + 1 then
                UI_PATTERN_NEXT_DEBUG.color = {255, 0, 0}
            else
                UI_PATTERN_NEXT_DEBUG.color = {0, 0, 0}
            end
        end

--    elseif MODE == MODE_DRUM then
--        render_drum()
    end
end

function ui_update_state_buttons()
    if UI_STEP_PRESSED then
        UI_STEP_DEBUG.color = {255, 255, 0}
    else
        UI_STEP_DEBUG.color = {0,0,0}
    end

    if UI_SHIFT_PRESSED then
        UI_SHIFT_DEBUG.color = {255, 0, 0}
    else
        UI_SHIFT_DEBUG.color = {0,0,0}
    end

    if UI_ALT_PRESSED then
        UI_ALT_DEBUG.color = {255, 0, 0}
    else
        UI_ALT_DEBUG.color = {0,0,0}
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
    }
    UI_PLAY_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "PLAY",
    }
    UI_STOP_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "STOP",
    }
    UI_REC_DEBUG = VB:button {
        width = 54,
        height = 35,
        text = "REC",
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
