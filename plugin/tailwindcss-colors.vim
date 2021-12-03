if exists('g:loaded_tailwindcss_colors')
  finish
endif

let g:loaded_tailwindcss_colors = 1

command! TailwindColorsAttach lua require('tailwindcss-colors').buf_attach()
command! TailwindColorsDetach lua require('tailwindcss-colors').buf_detach()
command! TailwindColorsStatus lua require('tailwindcss-colors').print_status()
