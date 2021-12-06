if exists('g:loaded_tailwindcss_colors')
  finish
endif

let g:loaded_tailwindcss_colors = 1

command! TailwindColorsAttach lua require('tailwindcss-colors').buf_attach()
command! TailwindColorsDetach lua require('tailwindcss-colors').buf_detach()
command! TailwindColorsToggle lua require('tailwindcss-colors').buf_toggle()
command! TailwindColorsRefresh lua require('tailwindcss-colors').update_highlight(vim.api.nvim_get_current_buf())