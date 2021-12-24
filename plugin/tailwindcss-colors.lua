if vim.g.loaded_tailwindcss_colors == 1 then
   return
end

vim.g.loaded_tailwindcss_colors = 1

vim.cmd "command! TailwindColorsAttach lua require('tailwindcss-colors').buf_attach()"
vim.cmd "command! TailwindColorsDetach lua require('tailwindcss-colors').buf_detach()"
vim.cmd "command! TailwindColorsToggle lua require('tailwindcss-colors').buf_toggle()"
vim.cmd "command! TailwindColorsRefresh lua require('tailwindcss-colors').buf_refresh()"
