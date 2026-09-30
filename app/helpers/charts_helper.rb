module ChartsHelper
  # Inline SVG bar chart (no JS/asset dependency, theme-aware via CSS vars).
  # points: [{ label:, value: }, ...]. Bars use --primary; labels use currentColor.
  def bar_chart_svg(points, height: 190, color: "var(--primary)")
    points = Array(points)
    return "".html_safe if points.empty?
    n      = points.size
    slot   = 58
    w      = n * slot
    top    = 22          # room for value labels
    bottom = height - 26 # baseline (room for month labels)
    plot_h = bottom - top
    max    = [ points.map { |p| p[:value].to_i }.max, 1 ].max
    bar_w  = (slot * 0.52).round

    bars = points.each_with_index.map do |p, i|
      cx  = (i * slot + slot / 2.0)
      val = p[:value].to_i
      bh  = (val.to_f / max * plot_h).round
      bh  = 3 if bh < 3 && val.positive?
      y   = bottom - bh
      x   = (cx - bar_w / 2.0).round
      <<~SVG
        <rect x="#{x}" y="#{y}" width="#{bar_w}" height="#{bh}" rx="6" fill="#{color}" opacity="#{val.zero? ? 0.15 : 1}"/>
        <text x="#{cx.round}" y="#{y - 6}" text-anchor="middle" font-size="12" font-weight="700" fill="currentColor">#{val}</text>
        <text x="#{cx.round}" y="#{height - 8}" text-anchor="middle" font-size="11" fill="currentColor" opacity=".55">#{ERB::Util.html_escape(p[:label])}</text>
      SVG
    end.join

    baseline = %(<line x1="0" y1="#{bottom}" x2="#{w}" y2="#{bottom}" stroke="currentColor" stroke-opacity=".12"/>)
    %(<svg viewBox="0 0 #{w} #{height}" width="100%" height="#{height}" preserveAspectRatio="xMidYMid meet" style="display:block; overflow:visible;" role="img">#{baseline}#{bars}</svg>).html_safe
  end

  # Inline SVG heatmap of activity by weekday × hour-of-day (no JS/asset deps).
  # matrix: [{ dow: 0..6, hours: [24 ints] }, ...] (dow 0 = Sun). Cell opacity
  # scales with count/max; --primary for the fill. day_labels = 7 short strings.
  def heatmap_svg(matrix, day_labels:, color: "var(--primary)")
    matrix = Array(matrix)
    return "".html_safe if matrix.empty?

    max = [ matrix.flat_map { |r| r[:hours] }.map(&:to_i).max.to_i, 1 ].max
    cell = 22
    gap  = 3
    left = 34   # room for weekday labels
    top  = 16   # room for hour labels
    cols = 24
    w = left + cols * (cell + gap)
    h = top + matrix.size * (cell + gap) + 6

    parts = []
    # Hour column labels (every 3h to avoid clutter).
    (0..23).each do |hr|
      next unless (hr % 3).zero?
      x = left + hr * (cell + gap) + cell / 2
      parts << %(<text x="#{x}" y="11" text-anchor="middle" font-size="9" fill="currentColor" opacity=".5">#{hr}h</text>)
    end

    matrix.each_with_index do |row, ri|
      y = top + ri * (cell + gap)
      label = day_labels[row[:dow].to_i] || row[:dow].to_s
      parts << %(<text x="0" y="#{y + cell / 2 + 3}" font-size="10" fill="currentColor" opacity=".6">#{ERB::Util.html_escape(label)}</text>)
      Array(row[:hours]).each_with_index do |c, hr|
        c = c.to_i
        x = left + hr * (cell + gap)
        op = c.zero? ? 0.06 : (0.15 + 0.85 * (c.to_f / max)).round(3)
        parts << %(<rect x="#{x}" y="#{y}" width="#{cell}" height="#{cell}" rx="4" fill="#{color}" fill-opacity="#{op}" stroke="transparent" stroke-width="2" style="cursor:pointer; transition:fill-opacity .1s;" data-count="#{c}" data-slot="#{ERB::Util.html_escape(label)} #{hr}h–#{hr + 1}h"></rect>)
      end
    end

    %(<svg viewBox="0 0 #{w} #{h}" width="100%" preserveAspectRatio="xMinYMin meet" style="display:block; min-width:#{w}px;" role="img">#{parts.join}</svg>).html_safe
  end
end
