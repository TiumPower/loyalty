module IconsHelper
  # Inline line-icon set (24×24, currentColor stroke) for the customer app.
  ICONS = {
    home:    %(<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5"/>),
    wallet:  %(<rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18"/><circle cx="17" cy="14" r="1.4" fill="currentColor" stroke="none"/>),
    gift:    %(<rect x="4" y="9" width="16" height="11" rx="2"/><path d="M4 13h16M12 9v11"/><path d="M12 9C10 9 8 8 8 6.5S9 4 10 4.5 12 7 12 9Zm0 0c2 0 4-1 4-2.5S15 4 14 4.5 12 7 12 9Z"/>),
    scan:    %(<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M4 12h16"/>),
    qrcode:  %(<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2v2M18 14h2M20 16v2M14 18v2h2M18 20h2" stroke-linecap="round"/>),
    wheel:   %(<circle cx="12" cy="12" r="9"/><path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6 5.6 18.4"/><circle cx="12" cy="12" r="2.2" fill="currentColor" stroke="none"/>),
    user:    %(<circle cx="12" cy="8" r="4"/><path d="M4 20c0-3.5 3.6-6 8-6s8 2.5 8 6"/>),
    bell:    %(<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6"/><path d="M10 19a2 2 0 0 0 4 0"/>),
    gear:    %(<circle cx="12" cy="12" r="3.2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1"/>),
    stamp:   %(<circle cx="12" cy="12" r="8"/><path d="m8.5 12 2.3 2.3 4.7-4.7"/>),
    target:  %(<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>),
    medal:   %(<circle cx="12" cy="14" r="6"/><path d="m9 4 3 5 3-5"/><path d="m10.5 13.5 1.5 1.5 3-3" stroke-linecap="round"/>),
    users:   %(<circle cx="9" cy="8" r="3.2"/><path d="M3 19c0-3 2.7-5 6-5s6 2 6 5"/><path d="M16 5.5a3 3 0 0 1 0 5.6M17 19c0-2.2-1-3.8-2.5-4.6"/>),
    history: %(<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3.5 4v3.5H7" stroke-linecap="round"/><path d="M12 8v4.2l2.8 1.7" stroke-linecap="round"/>),
    eye:     %(<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="3"/>),
    eye_off: %(<path d="M3 3l18 18" stroke-linecap="round"/><path d="M10.6 5.1A10.4 10.4 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-3.2 3.9M6.4 6.4A16.6 16.6 0 0 0 2.5 12S6 18.5 12 18.5a10 10 0 0 0 4-.8"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>),
    pause:   %(<rect x="7" y="5" width="3.4" height="14" rx="1.2"/><rect x="13.6" y="5" width="3.4" height="14" rx="1.2"/>),
    play:    %(<path d="M7.5 4.9 19 12 7.5 19.1Z" stroke-linejoin="round"/>),
    check:   %(<path d="M4.5 12.5 9.5 17.5 19.5 6.5" stroke-linecap="round"/>),
    launch:  %(<path d="M14 4h6v6" stroke-linecap="round"/><path d="M20 4 10 14" stroke-linecap="round"/><path d="M18 13.5V19a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5.5" stroke-linecap="round"/>),
    trash:   %(<path d="M4 7h16" stroke-linecap="round"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12"/><path d="M10 11v6M14 11v6" stroke-linecap="round"/>),
    menu:    %(<path d="M4 6h16M4 12h16M4 18h16"/>),
    # -- merchant sidebar (the admin design's six sections) --
    layout:    %(<rect x="3.5" y="3.5" width="7" height="8" rx="1.6"/><rect x="13.5" y="3.5" width="7" height="5" rx="1.6"/><rect x="13.5" y="10.5" width="7" height="10" rx="1.6"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.6"/>),
    store:     %(<path d="M4 9.5h16V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19Z"/><path d="M3.2 9.5 5 4.2h14l1.8 5.3"/><path d="M9.5 20.5v-5.2h5v5.2"/>),
    megaphone: %(<path d="M4 10.5v3a1.5 1.5 0 0 0 1.5 1.5H8l7.5 4.2V6.3L8 10.5H5.5A1.5 1.5 0 0 0 4 12Z"/><path d="M18.5 9.2a4 4 0 0 1 0 5.6"/><path d="M8 15v4.5" stroke-linecap="round"/>),
    # -- tab bar (shapes taken from the buyer design's nav) --
    wallet_cards: %(<rect x="3" y="5.5" width="18" height="13" rx="3"/><path d="M3 10.2h18"/><path d="M9.5 14.6h5" stroke-linecap="round"/>),
    award:       %(<circle cx="12" cy="9" r="5.2"/><path d="m8.6 13.4-1.3 6.4 4.7-2.6 4.7 2.6-1.3-6.4" stroke-linejoin="round"/>),
    user_circle: %(<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.4 18.6a6.3 6.3 0 0 1 11.2 0"/>),
    arrow_left:  %(<path d="M19 12H5"/><path d="m12 19-7-7 7-7"/>),
    arrow_right: %(<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>),
    chevron_right: %(<path d="m9 5 7 7-7 7"/>),
    chevron_left:  %(<path d="m15 5-7 7 7 7"/>),
    close:   %(<path d="M18 6 6 18M6 6l12 12"/>),
    plus:    %(<path d="M12 5v14M5 12h14"/>),
    # -- content --
    ticket:  %(<path d="M4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4Z"/><path d="M14 6v2M14 11v2M14 16v2" stroke-dasharray="2 2"/>),
    tag:     %(<path d="M11.6 3.5H19a1.5 1.5 0 0 1 1.5 1.5v7.4a2 2 0 0 1-.6 1.4l-6.6 6.6a1.5 1.5 0 0 1-2.1 0l-7.1-7.1a1.5 1.5 0 0 1 0-2.1l6.6-6.6a2 2 0 0 1 1.4-.6Z"/><circle cx="16" cy="8" r="1.3" fill="currentColor" stroke="none"/>),
    sparkles: %(<path d="M12 3.5 13.6 8 18 9.5 13.6 11 12 15.5 10.4 11 6 9.5 10.4 8Z"/><path d="M18.5 15.5 19.3 17.7 21.5 18.5 19.3 19.3 18.5 21.5 17.7 19.3 15.5 18.5 17.7 17.7Z"/>),
    star:    %(<path d="m12 3.6 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L3.5 9.8l5.9-.9Z"/>),
    coins:   %(<ellipse cx="9" cy="7" rx="5.5" ry="2.8"/><path d="M3.5 7v4c0 1.5 2.5 2.8 5.5 2.8s5.5-1.3 5.5-2.8V7"/><path d="M14.5 10.4c3 .2 6 1.4 6 2.9v4c0 1.5-2.5 2.8-5.5 2.8-2.2 0-4.1-.7-5-1.7"/>),
    receipt: %(<path d="M6 3.5h12v17l-2.4-1.6L13.2 20.5 10.8 19 8.4 20.5 6 18.9Z"/><path d="M9.2 8h5.6M9.2 11.5h5.6" stroke-linecap="round"/>),
    trophy:  %(<path d="M8 4h8v5a4 4 0 0 1-8 0Z"/><path d="M8 5.5H5.5A2.5 2.5 0 0 0 8 10M16 5.5h2.5A2.5 2.5 0 0 1 16 10"/><path d="M12 13v3.5M9 20h6" stroke-linecap="round"/>),
    flame:   %(<path d="M12 21c3.3 0 6-2.4 6-5.6 0-3.9-3.6-5.6-4.4-9.4C11.7 7.8 11 9.5 11 11c-1-.4-1.6-1.4-1.8-2.6C7.6 10 6 12.3 6 15.4 6 18.6 8.7 21 12 21Z"/>),
    lock:    %(<rect x="5" y="10.5" width="14" height="9.5" rx="2.2"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.6 0v2.5"/>),
    copy:    %(<rect x="9" y="9" width="11" height="11" rx="2.2"/><path d="M15 6.5A2.5 2.5 0 0 0 12.5 4H6.5A2.5 2.5 0 0 0 4 6.5v6A2.5 2.5 0 0 0 6.5 15"/>),
    share:   %(<circle cx="18" cy="5.5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="18.5" r="2.5"/><path d="m8.2 10.8 7.6-4M8.2 13.2l7.6 4"/>),
    refresh: %(<path d="M20.5 12a8.5 8.5 0 1 1-2.6-6.1"/><path d="M20.5 4v3.9h-3.9" stroke-linecap="round"/>),
    edit:    %(<path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17v3Z"/><path d="M14.5 6.5 17.5 9.5"/>),
    camera:  %(<path d="M4 8.5h3l1.4-2.2h7.2L17 8.5h3a1 1 0 0 1 1 1v8.5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9.5a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13.5" r="3.4"/>),
    # -- shop / contact --
    pin:     %(<path d="M12 21s7-5.6 7-11a7 7 0 1 0-14 0c0 5.4 7 11 7 11Z"/><circle cx="12" cy="10" r="2.6"/>),
    clock:   %(<circle cx="12" cy="12" r="8.5"/><path d="M12 7.2V12l3.2 2" stroke-linecap="round"/>),
    phone:   %(<path d="M6.2 3.5h3l1.4 3.6-2 1.4a12 12 0 0 0 5.9 5.9l1.4-2 3.6 1.4v3a2 2 0 0 1-2.2 2A16.5 16.5 0 0 1 4.2 5.7a2 2 0 0 1 2-2.2Z"/>),
    mail:    %(<rect x="3" y="5.5" width="18" height="13" rx="2.2"/><path d="m3.8 7 7.1 5.3a2 2 0 0 0 2.2 0L20.2 7"/>),
    navigate: %(<path d="M20.5 3.5 3.5 10.6l7.2 2.7 2.7 7.2Z"/>),
    globe:   %(<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5a13 13 0 0 1 0 17 13 13 0 0 1 0-17Z"/>),
    shield:  %(<path d="M12 3.2 19 6v5.5c0 4.3-2.9 7.6-7 9.3-4.1-1.7-7-5-7-9.3V6Z"/><path d="m9 12 2.2 2.2L15.2 10" stroke-linecap="round"/>),
    help:    %(<circle cx="12" cy="12" r="8.5"/><path d="M9.8 9.4A2.3 2.3 0 0 1 14.3 10c0 1.6-2.3 1.9-2.3 3.4" stroke-linecap="round"/><circle cx="12" cy="16.8" r=".9" fill="currentColor" stroke="none"/>),
    logout:  %(<path d="M15 4.5h2.5a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H15"/><path d="M10 8 6 12l4 4M6 12h9" stroke-linecap="round"/>)
  }.freeze

  # Hand-drawn marketing doodle, drawn client-side by sketch_controller (Rough.js).
  # Decorative only; draws itself in on reveal. Shapes: see RECIPES in that controller.
  def doodle(shape, klass: nil, i: 0)
    tag.svg(class: klass, style: ("--i:#{i}" if i.positive?), aria: { hidden: true },
            data: { controller: "sketch", sketch_shape_value: shape, reveal: "sketch" })
  end

  def ui_icon(name, size: 24, klass: nil, stroke: 1.8)
    body = ICONS[name.to_sym] or return "".html_safe
    attrs = %(viewBox="0 0 24 24" width="#{size}" height="#{size}" fill="none" stroke="currentColor" stroke-width="#{stroke}" stroke-linejoin="round" stroke-linecap="round" class="#{klass}" aria-hidden="true")
    "<svg #{attrs}>#{body}</svg>".html_safe
  end
end
