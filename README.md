# TagStyleTool - A Discorse tag design theme component

**TagStyleTool** is an inspired version of (3) existing components to allow customizing the appearance of tags on Discourse!

**Features:**

- Solved compatibility issues (Specifically between the remove dashes, and tag icons)
- Assign a Font Awesome icon to specific tags.
- Added the option to apply a default tag icon to any tag not defined. 
- Inverted inheritance e.g. label or text color
- Solves a contrast color issue with text color when using the label coloring setting.
- Allowed the ability to choose between the existing tag styles. 
- Versatility of settings allowing disabling of default tag, or dashes feature.
- Settings format is the same (with the addition of new settings) as [Tag Icons](https://meta.discourse.org/t/tag-icons/109757/163) allowing for portability/adoptability easily.
- Visual Style Builder allows for visual helpers to make styling tags a breeze. (see [Visual Style Builder](#visual-style-builder))


Concepts & Features directly adopted or inspired from the theme component projects below.

- [Discourse Tag Icons](https://github.com/discourse/discourse-tag-icons) (MIT License)
- [Tag Styles](https://gitlab.com/manuelkostka/discourse/helpers/tag-styles) (MIT License)
- [Remove Tag Dashes ](https://github.com/discourse/discourse-remove-dashes-from-tag-names) (GPL-2.0 License)

# Visual Style Builder

Released in v0.2, is a visual style builder, which is a fly-out panel with several helpers to choose from. 

- Import all the tags of a group
- Search FontAwesome's Icon database right in the builder for convenience. 
- Visual Colorpicker
