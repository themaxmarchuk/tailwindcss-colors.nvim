local M = {}

local bit = require "bit"

-- Adds hex string to a color and range pair
-- Also converts values (0 to 1) to (0 to 255) (8 bit int)
M.lsp_color_add_hex = function(lsp_color)
   -- converts from (0 to 1) space to (0 to 255) applying alpha
   local function to256(c)
      -- TODO: what's up with applying alpha (won't it usually be 1 anyways?)
      return math.floor(c * lsp_color.alpha * 255)
   end

   -- convert each component to (0 to 255) space
   lsp_color.red = to256(lsp_color.red)
   lsp_color.green = to256(lsp_color.green)
   lsp_color.blue = to256(lsp_color.blue)

   -- In theory having only one call to bit.tohex() and performing leftshifts
   -- with a binary or will result in faster conversion time

   -- Compute a character digit hex string (for use in creating the highlights)
   lsp_color.hex = bit.tohex(
      -- or all of the numbers together
      bit.bor(
         -- convert the red component an 8 bit integer and bitshift left 16 bits
         -- (2 color components)
         bit.lshift(lsp_color.red, 16),
         -- convert the green component an 8 bit integer and bitshift left 8 bits
         -- (1 color components)
         bit.lshift(lsp_color.green, 8),
         -- no need to left shift, this is the rightmost part of the color
         lsp_color.blue
      ),
      -- 6 characters in total
      6
   )

   return lsp_color
end

-- Determine whether to use black or white text
-- Ref: https://stackoverflow.com/a/1855903/837964
-- https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
M.color_is_bright = function(color)
   -- Counting the perceptive luminance - human eye favors green color
   local luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255
   if luminance > 0.5 then
      return true -- Bright colors, use dark text
   else
      return false -- Dark colors, use light text
   end
end

return M
