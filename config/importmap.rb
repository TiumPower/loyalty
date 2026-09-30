# Pin npm packages by running ./bin/importmap

pin "application"
pin "confirm_dialog"
pin "toast"
pin "jsqr" # vendored fallback QR decoder (browsers without BarcodeDetector)
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "marketing" # marketing layout only
pin "preline-collapse" # vendored Preline plugin, see header of vendor/javascript/preline-collapse.js
pin "roughjs" # vendored drawing lib, see header of vendor/javascript/roughjs.js
