# tailwindcss-colors.nvim
This plugin highlights Tailwind CSS class names when [@tailwindcss/language-server](https://github.com/tailwindlabs/tailwindcss-intellisense) is connected via the neovim built-in lsp client.

![Demo.gif](https://i.imgur.com/hDbxvBJ.gif)

---

## Requirements

- [Neovim 0.5+](https://github.com/neovim/neovim)
- [@tailwindcss/language-server](https://github.com/tailwindlabs/tailwindcss-intellisense)
  
  Can be installed with
  ```shell
  npm install -g @tailwindcss/language-server
  ```
  or with [nvim-lsp-installer](https://github.com/williamboman/nvim-lsp-installer)
  
  Don't forget to configure it after installation (via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) for example)

## Installation

Install using your favorite package manager (packer, vim-plug, etc).

[packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use {
  "themaxmarchuk/tailwindcss-colors.nvim",
  -- load only on require("tailwindcss-colors")
  module = "tailwindcss-colors"
  -- run the setup function after plugin is loaded 
  config = function ()
    -- pass config options here (or nothing to use defaults)
    require("tailwindcss-colors").setup()
  end
}
```

[vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'themaxmarchuk/tailwindcss-colors.nvim'
```
--- 
Alternatively, you can manually install it.

> Unix/Linux

```shell
git clone https://github.com/themaxmarchuk/tailwindcss-colors.nvim.git ~/.local/share/nvim/site/pack/tailwindcss-colors/start/
```

>Windows Command Prompt
```shell
git clone https://github.com/themaxmarchuk/tailwindcss-colors.nvim.git %LOCALAPPDATA%\nvim-data\site\pack\tailwindcss-colors\start\
```

>Windows Powershell
```shell
git clone https://github.com/themaxmarchuk/tailwindcss-colors.nvim.git "$env:LOCALAPPDATA\nvim-data\site\pack\packer\start\"
```
---

## Enabling the plugin

To enable the plugin you have two options. You can simply call `require("tailwindcss-colors").buf_attach(bufnr)` somewhere in your lsp `on_attach` function.

This can be done via builtin-lsp, [lsp-config](https://github.com/neovim/nvim-lspconfig), or  [nvim-lsp-installer](https://github.com/williamboman/nvim-lsp-installer) (in their `.setup()` functions).

> [lsp-config](https://github.com/neovim/nvim-lspconfig) example
```lua
local nvim_lsp = require("lspconfig")

local on_attach = function(client, bufnr)
  -- other stuff --
  require("tailwindcss-colors").buf_attach(bufnr)
end

nvim_lsp["tailwindcss"].setup({
  -- other settings --
  on_attach = on_attach,
})
```

> [NvChad](https://github.com/NvChad/NvChad)

If you use NvChad, you might have noticed that the lsp configuration already defines an on_attach function. 

In that case you can wrap it like this:
```lua
-- looping through server names ...

if lsp = "tailwindcss" then
  -- warp the attach function
  opts.on_attach = function (_, bufnr)
    require('tailwindcss-colors').buf_attach(bufnr)
    attach(_, bufnr)
  end
end
```
--- 
The other way to is the use commands to enable the plugin for the current buffer:

> `:TailwindColorsAttach` 

> `:TailwindColorsDetach`

> `:TailwindColorsToggle`

## Configuration

To configure, pass in your configuration options when you call the `require("tailwindcss-colors").setup({ .. config options .. })`

Note that calling the setup function is not required if you only want to use the default configuration.

> Default configuration
```lua
-- Default user configuration
local user_config = {
  colors = {
    dark = "#000000",  -- dark text color
    light = "#FFFFFF", -- light text color
  },
  commands = true -- should add commands
}
```

> Example
```lua
-- if using packer, you can do this in
-- use {
--   config = function ()
--     ...
--   end
-- }
-- (for lazy loading)

-- For example, this will disable commands,
-- but keep default colors for light/dark text
require("tailwindcss-colors").setup({
  commands = false
})
```

## Commands

Commands can be optionally disabled in the configuration, they are on by default.

> `:TailwindColorsAttach`

Attaches to the current buffer.

> `:TailwindColorsDetach`

Detaches from the current buffer.

> `:TailwindColorsRefresh`

Refreshes highlights in the current buffer (useful for auto commands)

> `:TailwindColorsToggle`

Toggles the highlighting in the current buffer. (same as attach/detach)

## Contributing

This is my first neovim plugin, and my first time writing any lua.

* Have an idea? 
* See a better way to do something?
* Found a bug?

Feel free to [submit a PR](https://github.com/themaxmarchuk/tailwindcss-colors.nvim/pulls).

## Credits
Inspired by [nvim-colorizer.lua](https://github.com/norcalli/nvim-colorizer.lua) and [kabouzeid](https://github.com/kabouzeid)'s [dotfiles](https://github.com/kabouzeid/dotfiles/blob/main/config/nvim/lua/lsp-documentcolors.lua)
