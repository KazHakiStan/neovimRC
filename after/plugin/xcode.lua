-- Xcode build / run / lldb debugging (macOS only): lua/kazhakistan/xcode
if not require("kazhakistan.platform").is_macos then return end

require("kazhakistan.xcode").setup()
