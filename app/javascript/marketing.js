// Loaded only by layouts/marketing. turbo:load also fires on first page load.
import HSCollapse from "preline-collapse"

addEventListener("turbo:load", () => HSCollapse.autoInit())
