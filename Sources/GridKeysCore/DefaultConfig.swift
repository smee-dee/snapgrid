public enum DefaultConfig {
    public static let text = """
    # GridKeys config. Reloads automatically when saved.
    #
    # cells = "col,row WxH"  →  0-based top-left cell, then width x height in cells.
    # keys  = modifiers (ctrl, alt/option, shift, cmd) + one key, joined with "+".
    #         Keys: letters/digits as labelled on your keyboard, left/right/up/down,
    #         return, space, tab, escape, f1–f20, pad0–pad9, keycode:<n>.

    [settings]
    grid = "6x6"            # default grid (columns x rows) for shortcuts without their own grid
    gap = 0                 # points between windows and around screen edges
    leader = "ctrl+alt+space"   # arms local shortcuts (global = false), like opening the Divvy panel
    leader_timeout = 3      # seconds local shortcuts stay armed

    [[shortcut]]
    name = "Left half"
    keys = "ctrl+alt+left"
    cells = "0,0 3x6"

    [[shortcut]]
    name = "Right half"
    keys = "ctrl+alt+right"
    cells = "3,0 3x6"

    [[shortcut]]
    name = "Top half"
    keys = "ctrl+alt+up"
    cells = "0,0 6x3"

    [[shortcut]]
    name = "Bottom half"
    keys = "ctrl+alt+down"
    cells = "0,3 6x3"

    [[shortcut]]
    name = "Maximize"
    keys = "ctrl+alt+return"
    cells = "0,0 6x6"

    [[shortcut]]
    name = "Center"
    keys = "ctrl+alt+c"
    cells = "1,1 4x4"

    [[shortcut]]
    name = "Left two thirds"
    keys = "ctrl+alt+e"
    grid = "3x1"
    cells = "0,0 2x1"

    [[shortcut]]
    name = "Right third"
    keys = "ctrl+alt+t"
    grid = "3x1"
    cells = "2,0 1x1"

    [[shortcut]]
    name = "Next display"
    keys = "ctrl+alt+cmd+right"
    action = "next-screen"

    [[shortcut]]
    name = "Previous display"
    keys = "ctrl+alt+cmd+left"
    action = "previous-screen"

    # Local shortcuts: press the leader, then the key.
    [[shortcut]]
    name = "Left half (local)"
    keys = "l"
    cells = "0,0 3x6"
    global = false

    [[shortcut]]
    name = "Right half (local)"
    keys = "r"
    cells = "3,0 3x6"
    global = false

    [[shortcut]]
    name = "Maximize (local)"
    keys = "m"
    cells = "0,0 6x6"
    global = false

    """
}
