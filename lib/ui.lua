-- lib/ui.lua
-- popup system for h-stex
-- based on ncoco's UI.draw_popup pattern

local UI = {}

UI.popup = {
   active = false,
   name = "",
   value = "",
   deadline = 0
}

function UI.show_popup(name, value, duration)
   duration = duration or 1.5
   UI.popup.name = name
   UI.popup.value = value
   UI.popup.active = true
   UI.popup.deadline = util.time() + duration
end

function UI.draw_popup()
   if UI.popup.active then
      if util.time() > UI.popup.deadline then
         UI.popup.active = false
      else
         screen.font_size(8)
         screen.level(0)
         screen.rect(10, 50, 108, 12)
         screen.fill()
         screen.level(15)
         screen.rect(10, 50, 108, 12)
         screen.stroke()
         screen.move(64, 58)
         screen.text_center(UI.popup.name .. ": " .. UI.popup.value)
      end
   end
end

return UI