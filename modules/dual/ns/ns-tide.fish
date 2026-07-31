# Tide prompt integration for `ns` — installed only when
# programs.ns.tideBadges.enable = true. Provides THREE separate right-prompt
# sections, in order:
#   1. ns_mode — the mode (isolated / rehearse) with its mode icon
#   2. ns_net  — the network state (online = globe, offline = airplane)
#   3. ns_pkgs — the injected packages, prefixed with the default ns flask icon
# Splitting them keeps each unambiguous (e.g. "isolated" can't read as
# "network isolated"). Live shells show only ns_pkgs (the flask + packages).
# Plus Level-3 per-mode accents (prompt character + PWD segment) for the
# sandbox modes. Loaded from conf.d after the base theme (00-) and before Tide
# bakes; NS_MODE/NS_INFO/NS_NET are exported so they reach Tide's background
# `fish -c` render child. See docs/spec-ephemeral-shells.md §4.

# Section styles (black text on light backgrounds unless noted).
set -g tide_ns_isolated_bg_color D7AF5F # sand   — ! isolated (cube)
set -g tide_ns_isolated_color 000000
set -g tide_ns_isolated_icon 
set -g tide_ns_rehearse_bg_color AF87FF # violet — @ rehearse (recycle)
set -g tide_ns_rehearse_color 000000
set -g tide_ns_rehearse_icon 
set -g tide_ns_net_on_bg_color 5FAFD7 # teal   — online (globe)
set -g tide_ns_net_on_color 000000
set -g tide_ns_net_on_icon 
set -g tide_ns_net_off_bg_color CC0000 # red    — offline (airplane)
set -g tide_ns_net_off_color FFFFFF
set -g tide_ns_net_off_icon 
set -g tide_ns_pkgs_bg_color FF5D5D # coral  — packages (flask, the default ns icon)
set -g tide_ns_pkgs_color 000000
set -g tide_ns_pkgs_icon 

# Add the three items to the right prompt, in order (base theme owns the rest).
set -a tide_right_prompt_items ns_mode ns_net ns_pkgs

# 1. Mode section — sandbox modes only (live has no mode badge).
function _tide_item_ns_mode
    set -q NS_MODE; or return
    switch $NS_MODE
        case isolated
            _tide_print_item ns_isolated $tide_ns_isolated_icon' ' isolated
        case rehearse
            _tide_print_item ns_rehearse $tide_ns_rehearse_icon' ' rehearse
    end
end

# 2. Network section — only in the sandbox modes (NS_NET is set there).
function _tide_item_ns_net
    set -q NS_NET; or return
    switch $NS_NET
        case net
            _tide_print_item ns_net_on $tide_ns_net_on_icon' ' online
        case no-net
            _tide_print_item ns_net_off $tide_ns_net_off_icon' ' offline
    end
end

# 3. Packages section — the flask icon + the injected package list. Shown in
# any ns shell that has packages (including live).
function _tide_item_ns_pkgs
    set -q NS_MODE; and test -n "$NS_INFO"; or return
    _tide_print_item ns_pkgs $tide_ns_pkgs_icon' ' $NS_INFO
end

# Level-3 per-mode accents: recolor the prompt character + PWD segment for the
# sandbox modes (live stays visually normal). Git/status colors are left alone
# so their meaning-carrying colors survive. Black PWD text for contrast on the
# light accent backgrounds.
switch "$NS_MODE"
    case isolated
        set -g tide_character_color D7AF5F
        set -g tide_pwd_bg_color D7AF5F
        set -g tide_pwd_color_dirs 000000
        set -g tide_pwd_color_anchors 000000
        set -g tide_pwd_color_truncated_dirs 000000
    case rehearse
        set -g tide_character_color AF87FF
        set -g tide_pwd_bg_color AF87FF
        set -g tide_pwd_color_dirs 000000
        set -g tide_pwd_color_anchors 000000
        set -g tide_pwd_color_truncated_dirs 000000
end
