if exists('g:loaded_tailwindcss_colors')
  finish
endif

let g:loaded_tailwindcss_colors = 1

command! TailwindColorsAttach lua require('tailwind_colors').buf_attach()
command! TailwindColorsDetach lua require('tailwind_colors').buf_detach()
